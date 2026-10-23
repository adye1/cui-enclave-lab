#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run on DC01 as CORP\Administrator. Creates fictional test accounts and places them in the
           right OUs and groups so access to \\FS01\CUI can be tested (allowed AND denied).
.NOTES     You are prompted for each password (14+ characters to meet the domain policy). Nothing is stored.
           Use a password manager; do not reuse any real password.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$dom  = Get-ADDomain
$root = $dom.DistinguishedName

$users = @(
  @{ Sam = 'cui.user1'; Name = 'CUI Test User 1'; Path = "OU=Users,OU=CUI-Enclave,$root"; Groups = @('CUI-Users') }
  @{ Sam = 'cui.user2'; Name = 'CUI Test User 2'; Path = "OU=Users,OU=CUI-Enclave,$root"; Groups = @('CUI-Users') }
  @{ Sam = 'cui.admin'; Name = 'CUI Test Admin';  Path = "OU=Users,OU=CUI-Enclave,$root"; Groups = @('CUI-Users', 'CUI-Admins') }
  @{ Sam = 'corp.user1'; Name = 'Corp Test User 1'; Path = "OU=Users,OU=Corp,$root";      Groups = @('Corp-Users') }   # deliberately NOT in CUI-Users
)
foreach ($u in $users) {
  if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue)) {
    $pw = Read-Host "Password for $($u.Sam) (14+ characters, upper/lower/number/symbol)" -AsSecureString
    New-ADUser -Name $u.Name -SamAccountName $u.Sam -UserPrincipalName "$($u.Sam)@$($dom.DNSRoot)" -Path $u.Path `
               -AccountPassword $pw -Enabled $true -ChangePasswordAtLogon $false
  } else { Write-Warning "$($u.Sam) exists - skipping creation." }
  foreach ($g in $u.Groups) { Add-ADGroupMember -Identity $g -Members $u.Sam -ErrorAction SilentlyContinue }
}

New-Item -ItemType Directory -Force 'C:\Lab\evidence' | Out-Null
foreach ($g in 'CUI-Users', 'CUI-Admins', 'Corp-Users') {
  "== $g ==" | Out-File 'C:\Lab\evidence\ad-group-membership.txt' -Append
  Get-ADGroupMember $g | Select-Object Name, SamAccountName | Format-Table -AutoSize | Out-File 'C:\Lab\evidence\ad-group-membership.txt' -Append
}
Write-Host 'Accounts created. Membership report: C:\Lab\evidence\ad-group-membership.txt' -ForegroundColor Green
