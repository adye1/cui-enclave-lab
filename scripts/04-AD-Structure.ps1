#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run INSIDE DC01 after both DCs are promoted and replicating.
           Builds the tiered-admin OU model, groups, password policy, a baseline GPO,
           DNS forwarders, and writes an evidence report to C:\Lab\evidence.
.NOTES     Admin account passwords are prompted for, never stored.
#>
[CmdletBinding()]
param(
  [string]$AdminName = 'adam',                  # creates t0-<name> and a standard user <name>
  [string[]]$DnsForwarders = @('1.1.1.1', '9.9.9.9')
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory, GroupPolicy
$dom = Get-ADDomain
$root = $dom.DistinguishedName

function New-LabOU([string]$Name, [string]$Path) {
  $dn = "OU=$Name,$Path"
  if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $true
  }
  $dn
}

# --- OU model: three tiers, a CUI enclave, and ordinary corporate objects ----
$ou = @{}
foreach ($t in @{ Tier0=@('Accounts','Servers','Groups'); Tier1=@('Accounts','Servers','Groups'); Tier2=@('Accounts','Workstations','Groups');
                  'CUI-Enclave'=@('Users','Servers','Workstations','Groups'); Corp=@('Users','Workstations'); ServiceAccounts=@() }.GetEnumerator()) {
  $top = New-LabOU $t.Key $root
  $ou[$t.Key] = $top
  foreach ($c in $t.Value) { $ou["$($t.Key)/$c"] = New-LabOU $c $top }
}

# --- Groups ------------------------------------------------------------------
$groups = @(
  @{ N='T0-Admins';  P=$ou['Tier0/Groups'] }, @{ N='T1-Admins'; P=$ou['Tier1/Groups'] }, @{ N='T2-Admins'; P=$ou['Tier2/Groups'] },
  @{ N='CUI-Users';  P=$ou['CUI-Enclave/Groups'] }, @{ N='CUI-Admins'; P=$ou['CUI-Enclave/Groups'] },
  @{ N='Corp-Users'; P=$ou['Corp/Users'] }
)
foreach ($g in $groups) {
  if (-not (Get-ADGroup -Filter "Name -eq '$($g.N)'" -ErrorAction SilentlyContinue)) { New-ADGroup -Name $g.N -GroupScope Global -Path $g.P }
}

# --- Password and lockout policy (aligned to NIST 800-171 IA / AC families) ---
Set-ADDefaultDomainPasswordPolicy -Identity $dom.DNSRoot -MinPasswordLength 14 -ComplexityEnabled $true `
  -PasswordHistoryCount 24 -MinPasswordAge '1.00:00:00' -MaxPasswordAge '365.00:00:00' `
  -LockoutThreshold 5 -LockoutDuration '00:15:00' -LockoutObservationWindow '00:15:00'

# --- Separate admin and standard accounts for the owner ----------------------
function New-LabUser([string]$Sam, [string]$Path, [string]$Display) {
  if (Get-ADUser -Filter "SamAccountName -eq '$Sam'" -ErrorAction SilentlyContinue) { Write-Warning "$Sam exists - skipping."; return }
  $pw = Read-Host "Password for $Sam" -AsSecureString
  New-ADUser -Name $Display -SamAccountName $Sam -UserPrincipalName "$Sam@$($dom.DNSRoot)" -Path $Path `
             -AccountPassword $pw -Enabled $true -ChangePasswordAtLogon $false
}
New-LabUser "t0-$AdminName" $ou['Tier0/Accounts'] "T0 Admin $AdminName"
New-LabUser $AdminName      $ou['Corp/Users']     "$AdminName (standard)"
if (Get-ADUser -Filter "SamAccountName -eq 't0-$AdminName'" -ErrorAction SilentlyContinue) {
  Add-ADGroupMember -Identity 'Domain Admins'   -Members "t0-$AdminName" -ErrorAction SilentlyContinue
  Add-ADGroupMember -Identity 'T0-Admins'       -Members "t0-$AdminName" -ErrorAction SilentlyContinue
  Add-ADGroupMember -Identity 'Protected Users' -Members "t0-$AdminName" -ErrorAction SilentlyContinue
}
if (Get-ADUser -Filter "SamAccountName -eq '$AdminName'" -ErrorAction SilentlyContinue) {
  Add-ADGroupMember -Identity 'Corp-Users' -Members $AdminName -ErrorAction SilentlyContinue
}

# --- Baseline GPO linked to the CUI enclave and Tier 0 ------------------------
$gpoName = 'LAB-Baseline-Security'
$gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
if (-not $gpo) { $gpo = New-GPO -Name $gpoName }
$k = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Set-GPRegistryValue -Name $gpoName -Key $k -ValueName InactivityTimeoutSecs -Type DWord  -Value 900 | Out-Null   # 15 min session lock
Set-GPRegistryValue -Name $gpoName -Key $k -ValueName legalnoticecaption   -Type String -Value 'AUTHORIZED USE ONLY' | Out-Null
Set-GPRegistryValue -Name $gpoName -Key $k -ValueName legalnoticetext      -Type String -Value 'This is a lab system. Activity is monitored. Unauthorized use is prohibited. Mock data only.' | Out-Null
foreach ($target in $ou['CUI-Enclave'], $ou['Tier0']) {
  $linked = @((Get-GPInheritance -Target $target).GpoLinks | Where-Object DisplayName -eq $gpoName)
  if (-not $linked) { New-GPLink -Name $gpoName -Target $target | Out-Null }
}

# --- DNS: forward outside names (through the firewall) -------------------------
foreach ($f in $DnsForwarders) { Add-DnsServerForwarder -IPAddress $f -ErrorAction SilentlyContinue }

# --- Evidence report ------------------------------------------------------------
$ev = 'C:\Lab\evidence'; New-Item -ItemType Directory -Force $ev | Out-Null
Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName | Export-Csv "$ev\ad-ous.csv" -NoTypeInformation
Get-ADGroup -Filter * -SearchBase $root | Select-Object Name, GroupScope, DistinguishedName | Export-Csv "$ev\ad-groups.csv" -NoTypeInformation
Get-ADDefaultDomainPasswordPolicy | Format-List | Out-File "$ev\ad-password-policy.txt"
Get-GPOReport -Name $gpoName -ReportType Html -Path "$ev\gpo-$gpoName.html"
repadmin /replsummary | Out-File "$ev\ad-replication.txt"
dcdiag /q | Out-File "$ev\dcdiag.txt"
Write-Host "Done. Evidence written to $ev" -ForegroundColor Green
