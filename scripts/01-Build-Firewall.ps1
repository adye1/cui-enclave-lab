#Requires -RunAsAdministrator
<#
.SYNOPSIS  Phase 1: create FW01 (OPNsense) with one NIC per segment and fixed MACs.
.EXAMPLE   .\01-Build-Firewall.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$IsoRoot = 'F:\ISOs')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LabCommon.ps1"

# Fixed MACs so OPNsense interface assignment (hn0..hn5) is deterministic and documented.
$nics = @(
  @{ Switch='Lab-WAN';    Mac='00155D100001'; Ip='192.168.100.2/24'; Note='WAN, gateway 192.168.100.1 (host NAT)' }
  @{ Switch='Lab-Corp';   Mac='00155D100002'; Ip='10.20.0.1/24' }
  @{ Switch='Lab-CUI';    Mac='00155D100003'; Ip='10.30.0.1/24' }
  @{ Switch='Lab-DMZ';    Mac='00155D100004'; Ip='10.40.0.1/24' }
  @{ Switch='Lab-Admin';  Mac='00155D100005'; Ip='10.50.0.1/24' }
  @{ Switch='Lab-Attack'; Mac='00155D100006'; Ip='10.60.0.1/24' }
)
$iso = Resolve-LabIso -Pattern '*OPNsense*' -IsoRoot $IsoRoot
# Generation 1: the OPNsense DVD ISO has a BIOS-only boot catalog, so a UEFI (Gen 2) VM cannot boot it.
New-LabVM -Name FW01 -OS BSD -Generation 1 -MemoryGB 4 -vCPU 2 -DiskGB 30 `
          -Switch $nics.Switch -Mac $nics.Mac -Iso $iso

"`nFW01 interface plan (assign in this order in the OPNsense console):"
$i = 0
$nics | ForEach-Object {
  [pscustomobject]@{ If="hn$i"; Switch=$_.Switch; MAC=$_.Mac; IP=$_.Ip; Note=$_.Note }
  $i++
} | Format-Table -AutoSize
"Next: start FW01, install OPNsense, then follow docs\01-opnsense.md"
