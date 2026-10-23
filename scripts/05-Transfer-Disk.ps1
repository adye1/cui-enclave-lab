#Requires -RunAsAdministrator
<#
.SYNOPSIS  HOST script. Manages a small virtual disk used to move PKI files to and from the
           offline root CA (PKI-ROOT has no network adapter by design).
.EXAMPLE   .\05-Transfer-Disk.ps1 -Action Create
.EXAMPLE   .\05-Transfer-Disk.ps1 -Action Attach -VM PKI-ROOT
.EXAMPLE   .\05-Transfer-Disk.ps1 -Action Detach -VM PKI-ROOT
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Create', 'Attach', 'Detach')][string]$Action,
  [string]$VM,
  [string]$Path = 'F:\Transfer\pki-transfer.vhdx'
)
$ErrorActionPreference = 'Stop'

switch ($Action) {
  'Create' {
    if (Test-Path $Path) { throw "$Path already exists." }
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    New-VHD -Path $Path -SizeBytes 512MB -Dynamic | Out-Null
    $disk = Mount-VHD -Path $Path -Passthru | Initialize-Disk -PartitionStyle GPT -Passthru
    $part = $disk | New-Partition -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $part -FileSystem NTFS -NewFileSystemLabel 'PKI-XFER' -Confirm:$false | Out-Null
    Dismount-VHD -Path $Path
    "Created $Path (volume label PKI-XFER)."
  }
  'Attach' {
    if (-not $VM) { throw '-VM is required.' }
    if (-not (Test-Path $Path)) { throw "$Path not found. Run -Action Create first." }
    if (-not (Get-VMHardDiskDrive -VMName $VM | Where-Object Path -eq $Path)) { Add-VMHardDiskDrive -VMName $VM -Path $Path }
    "Attached to $VM. Inside the VM the disk shows as volume PKI-XFER."
  }
  'Detach' {
    if (-not $VM) { throw '-VM is required.' }
    Get-VMHardDiskDrive -VMName $VM | Where-Object Path -eq $Path | Remove-VMHardDiskDrive
    "Detached from $VM."
  }
}
