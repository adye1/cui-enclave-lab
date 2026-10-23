#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run INSIDE DC02, after DC01 has rebooted and is serving the domain.
           Sets the static IP, then promotes DC02 as a second domain controller.
.NOTES     Prompts for domain admin credentials and a DSRM password; nothing is stored.
#>
[CmdletBinding()]
param(
  [string]$DomainName = 'corp.lab.internal',
  [string]$Ip         = '10.50.0.11',
  [string]$Gateway    = '10.50.0.1',
  [string]$PrimaryDns = '10.50.0.10'
)
$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DC02') { throw "This script is for DC02 (this is $env:COMPUTERNAME)." }

$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $nic) { throw 'No connected network adapter found.' }
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $Ip -PrefixLength 24 -DefaultGateway $Gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $PrimaryDns

# --- Make sure DC01 is really answering before we try to join ----------------
$reachable = $false
for ($i = 1; $i -le 10 -and -not $reachable; $i++) {
  $reachable = [bool](ping.exe -n 1 -w 2000 $PrimaryDns | Select-String 'TTL=')
  if (-not $reachable) { Write-Host "Waiting for DC01 ($i/10)..."; Start-Sleep -Seconds 3 }
}
if (-not $reachable) { throw "Cannot reach DC01 at $PrimaryDns." }
try { Resolve-DnsName $DomainName -Server $PrimaryDns -ErrorAction Stop | Out-Null }
catch { throw "DC01 is not resolving $DomainName yet. Wait for it to finish rebooting and retry." }

Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
$cred = Get-Credential -Message "Domain admin for $DomainName (for example CORP\Administrator)"
$dsrm = Read-Host 'Enter a DSRM (safe mode) password for DC02' -AsSecureString
Install-ADDSDomainController -DomainName $DomainName -Credential $cred -InstallDns `
                             -SafeModeAdministratorPassword $dsrm -Force
