#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run INSIDE a new member server or workstation. Sets the static IP and DNS, checks the
           firewall rules let it reach the domain controllers, renames the machine, and joins the
           domain into the right OU. Reboots when done.
.EXAMPLE   .\10-Join-Domain.ps1 -Name FS01 -Ip 10.30.0.10 -Gateway 10.30.0.1 -OU 'OU=Servers,OU=CUI-Enclave'
.EXAMPLE   .\10-Join-Domain.ps1 -Name WS01 -Ip 10.30.0.21 -Gateway 10.30.0.1 -OU 'OU=Workstations,OU=CUI-Enclave'
.NOTES     You are prompted for CORP\Administrator credentials; nothing is stored.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)][string]$Ip,
  [Parameter(Mandatory)][string]$Gateway,
  [Parameter(Mandatory)][string]$OU,                 # relative to the domain root, e.g. 'OU=Servers,OU=CUI-Enclave'
  [string]$DomainName = 'corp.lab.internal',
  [string[]]$Dns = @('10.50.0.10', '10.50.0.11')
)
$ErrorActionPreference = 'Stop'

$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $nic) { throw 'No connected network adapter found.' }
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $Ip -PrefixLength 24 -DefaultGateway $Gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $Dns

# --- Prove the firewall rules are in place before attempting the join ---------
function Test-Port($port) {
  for ($i = 1; $i -le 5; $i++) {
    if ((Test-NetConnection $Dns[0] -Port $port -WarningAction SilentlyContinue).TcpTestSucceeded) { return $true }
    Start-Sleep 3
  }
  $false
}
# No gateway ping: the enclave rules deliberately do not allow ICMP to the firewall. Reaching the
# domain controllers through the gateway is the real test of the path.
$checks = [ordered]@{}
foreach ($p in 53, 88, 135, 389, 445) { $checks["DC01 TCP $p"] = Test-Port $p }
$checks.GetEnumerator() | ForEach-Object { '{0,-22} {1}' -f $_.Key, $(if ($_.Value) { 'ok' } else { 'BLOCKED' }) }
if ($checks.Values -contains $false) {
  throw 'Some paths are blocked. Check the CUI or Corp rules in OPNsense (docs\02-opnsense-rules.md), then rerun.'
}
try { Resolve-DnsName $DomainName -Server $Dns[0] -ErrorAction Stop | Out-Null }
catch { throw "DNS on $($Dns[0]) did not resolve $DomainName." }

# --- Join (and rename) into the correct OU ------------------------------------
$domainDn = 'DC=' + ($DomainName -split '\.' -join ',DC=')
$cred = Get-Credential -UserName 'CORP\Administrator' -Message "Domain admin to join $Name to $DomainName"
# Join first, rename second. Doing both in one Add-Computer call can fail with "The directory service is busy"
# because the rename hits the domain controller before the new computer object has settled.
Add-Computer -DomainName $DomainName -OUPath "$OU,$domainDn" -Credential $cred
if ($env:COMPUTERNAME -ne $Name) {
  Start-Sleep -Seconds 15
  Rename-Computer -NewName $Name -DomainCredential $cred -Force
}
Restart-Computer -Force
