#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Phase 0: prepare the Z840 for the CMMC enclave + AI governance labs.
  Creates folder layout, sets Hyper-V defaults, builds segmented virtual switches.
.EXAMPLE
  .\00-Initialize-Host.ps1 -WhatIf     # preview only
  .\00-Initialize-Host.ps1             # apply
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$CmmcDrive = 'D:', [string]$AiDrive = 'E:', [string]$ArchiveDrive = 'F:'
)
$ErrorActionPreference = 'Stop'

# --- 1. Folder layout -------------------------------------------------------
$folders = @(
  "$CmmcDrive\Hyper-V\VMs", "$CmmcDrive\Hyper-V\VHDs",
  "$AiDrive\AI-Lab\models", "$AiDrive\AI-Lab\datasets", "$AiDrive\AI-Lab\reports", "$AiDrive\AI-Lab\targets",
  "$ArchiveDrive\ISOs", "$ArchiveDrive\GoldenImages", "$ArchiveDrive\Checkpoints", "$ArchiveDrive\Evidence", "$ArchiveDrive\Backups"
)
foreach ($f in $folders) {
  if (-not (Test-Path $f) -and $PSCmdlet.ShouldProcess($f, 'Create folder')) { New-Item -ItemType Directory -Path $f | Out-Null }
}

# --- 2. Hyper-V defaults ----------------------------------------------------
# Service check works in Windows PowerShell and PowerShell 7 (Get-WindowsOptionalFeature
# fails in PS7 on some hosts with "Class not registered").
$vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue
if (-not $vmms -or $vmms.Status -ne 'Running' -or -not (Get-Command Get-VMHost -ErrorAction SilentlyContinue)) {
  throw 'Hyper-V management service (vmms) is not running or the Hyper-V PowerShell module is missing. Enable Hyper-V (including Management Tools) and reboot first.'
}
if ($PSCmdlet.ShouldProcess('Hyper-V host', "Set default VM/VHD paths on $CmmcDrive")) {
  Set-VMHost -VirtualMachinePath "$CmmcDrive\Hyper-V\VMs" -VirtualHardDiskPath "$CmmcDrive\Hyper-V\VHDs"
}

# --- 3. Network segments ----------------------------------------------------
# Lab-WAN is the only switch with a path out (host NAT). Everything else is private
# and can only be routed through OPNsense, which is what makes segmentation provable.
$switches = @(
  @{ Name='Lab-WAN';    Type='Internal'; Note='OPNsense WAN, NAT to internet (192.168.100.0/24)' },
  @{ Name='Lab-Corp';   Type='Private';  Note='Corporate users 10.20.0.0/24' },
  @{ Name='Lab-CUI';    Type='Private';  Note='CUI enclave 10.30.0.0/24' },
  @{ Name='Lab-DMZ';    Type='Private';  Note='DMZ / services 10.40.0.0/24' },
  @{ Name='Lab-Admin';  Type='Private';  Note='Tiered admin / PKI / SIEM 10.50.0.0/24' },
  @{ Name='Lab-Attack'; Type='Private';  Note='Attacker VM, adversary simulation 10.60.0.0/24' },
  @{ Name='Lab-Isolated'; Type='Private'; Note='Offline root CA only. Nothing else may ever connect here.' }
)
foreach ($s in $switches) {
  if (-not (Get-VMSwitch -Name $s.Name -ErrorAction SilentlyContinue) -and
      $PSCmdlet.ShouldProcess($s.Name, "Create $($s.Type) switch - $($s.Note)")) {
    New-VMSwitch -Name $s.Name -SwitchType $s.Type | Out-Null
  }
}

# Host-side NAT for Lab-WAN
if ($PSCmdlet.ShouldProcess('Lab-WAN', 'Assign host IP 192.168.100.1/24 and create NAT')) {
  $if = Get-NetAdapter | Where-Object Name -like '*Lab-WAN*'
  if ($if -and -not (Get-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress 192.168.100.1 -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress 192.168.100.1 -PrefixLength 24 | Out-Null
  }
  if (-not (Get-NetNat -Name 'LabNAT' -ErrorAction SilentlyContinue)) {
    try { New-NetNat -Name 'LabNAT' -InternalIPInterfaceAddressPrefix 192.168.100.0/24 | Out-Null }
    catch { Write-Warning "NAT not created (another NAT may already exist, e.g. WSL/Docker): $($_.Exception.Message)" }
  }
}

# --- 4. Summary -------------------------------------------------------------
Get-VMHost | Select-Object VirtualMachinePath, VirtualHardDiskPath | Format-List
Get-VMSwitch | Where-Object Name -like 'Lab-*' | Select-Object Name, SwitchType | Format-Table -AutoSize
