#Requires -RunAsAdministrator
<#
.SYNOPSIS  Phases 2-6: create the remaining lab VMs from LabVMs.psd1 (shells only; you install the OS).
.EXAMPLE   .\02-New-LabVMs.ps1 -WhatIf
.EXAMPLE   .\02-New-LabVMs.ps1 -Only DC01,DC02
#>
[CmdletBinding(SupportsShouldProcess)]
param([string[]]$Only, [string]$IsoRoot = 'F:\ISOs')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabCommon.ps1"

$specs = (Import-PowerShellDataFile "$PSScriptRoot\LabVMs.psd1").VMs
if ($Only) { $specs = $specs | Where-Object { $_.Name -in $Only } }
foreach ($s in $specs) {
  $iso = Resolve-LabIso -Pattern $s.IsoPattern -IsoRoot $IsoRoot
  New-LabVM -Name $s.Name -OS $s.OS -MemoryGB $s.MemoryGB -vCPU $s.vCPU -DiskGB $s.DiskGB `
            -Switch $s.Switch -Iso $iso -Tpm:([bool]$s.Tpm)
}
$total = ($specs | Measure-Object MemoryGB -Sum).Sum
"`nRAM allocated by this run: ${total}GB (FW01 adds 4GB; host has 128GB)."
