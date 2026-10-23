#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run INSIDE DC01. Sets its static IP, installs AD DS + DNS, and creates the forest.
           The server reboots when promotion finishes.
.NOTES     You are prompted for the DSRM (safe mode) password. It is never stored in this file.
#>
[CmdletBinding()]
param(
  [string]$DomainName = 'corp.lab.internal',
  [string]$NetBios    = 'CORP',
  [string]$Ip         = '10.50.0.10',
  [string]$Gateway    = '10.50.0.1'
)
$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DC01') { throw "This script is for DC01 (this is $env:COMPUTERNAME)." }

# --- Static IP; DNS points at itself because DC01 will host the zone ---------
$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $nic) { throw 'No connected network adapter found.' }
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $Ip -PrefixLength 24 -DefaultGateway $Gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses '127.0.0.1'

# --- Connectivity check before promoting -------------------------------------
$reachable = $false
for ($i = 1; $i -le 10 -and -not $reachable; $i++) {
  $reachable = [bool](ping.exe -n 1 -w 2000 $Gateway | Select-String 'TTL=')
  if (-not $reachable) { Write-Host "Waiting for network ($i/10)..."; Start-Sleep -Seconds 3 }
}
if (-not $reachable) { throw "Cannot reach the firewall at $Gateway. Check the Admin firewall rule and that DC01's NIC is on Lab-Admin." }

# --- Install roles and create the forest -------------------------------------
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
$dsrm = Read-Host 'Enter a DSRM (safe mode) password' -AsSecureString
Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetBios -InstallDns `
                   -SafeModeAdministratorPassword $dsrm -Force
