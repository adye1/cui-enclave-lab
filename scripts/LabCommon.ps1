# Shared helpers. Dot-source from the phase scripts:  . "$PSScriptRoot\LabCommon.ps1"

function Resolve-LabIso {
  param([string]$Pattern, [string]$IsoRoot = 'F:\ISOs')
  if (-not $Pattern) { return $null }
  # Match on name and require a real .iso (ignores leftovers like .iso.bz2).
  Get-ChildItem -Path $IsoRoot -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.iso' -and $_.Name -like $Pattern } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

function New-LabVM {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)][string]$Name,
    [int]$MemoryGB = 4,
    [int]$vCPU = 2,
    [int]$DiskGB = 60,
    [string[]]$Switch = @(),          # one NIC per entry, in order; empty = air-gapped VM
    [string[]]$Mac = @(),             # optional static MACs matching $Switch (12 hex digits)
    [string]$Iso,
    [ValidateSet('Windows', 'Linux', 'BSD')][string]$OS = 'Windows',
    [ValidateSet(1, 2)][int]$Generation = 2,   # 1 = BIOS (needed for ISOs with no UEFI boot entry, e.g. OPNsense DVD)
    [switch]$Tpm
  )
  if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { Write-Warning "$Name already exists - skipping."; return }
  foreach ($s in $Switch) { if (-not (Get-VMSwitch -Name $s -ErrorAction SilentlyContinue)) { throw "Switch '$s' missing. Run 00-Initialize-Host.ps1." } }

  $h = Get-VMHost
  $vhd = Join-Path $h.VirtualHardDiskPath "$Name.vhdx"
  if (-not $PSCmdlet.ShouldProcess($Name, "Create VM ($vCPU vCPU, ${MemoryGB}GB RAM, ${DiskGB}GB disk, NICs: $($Switch -join ', '))")) { return }

  New-VM -Name $Name -Generation $Generation -MemoryStartupBytes ([int64]$MemoryGB * 1GB) `
         -NewVHDPath $vhd -NewVHDSizeBytes ([int64]$DiskGB * 1GB) -Path $h.VirtualMachinePath | Out-Null
  Get-VMNetworkAdapter -VMName $Name | Remove-VMNetworkAdapter      # drop the default unconnected NIC
  Set-VM -Name $Name -AutomaticCheckpointsEnabled $false -AutomaticStartAction Nothing
  Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false
  Set-VMProcessor -VMName $Name -Count $vCPU

  for ($i = 0; $i -lt $Switch.Count; $i++) {
    $p = @{ VMName = $Name; Name = $Switch[$i]; SwitchName = $Switch[$i] }
    if ($Mac.Count -gt $i) { $p.StaticMacAddress = $Mac[$i] }
    Add-VMNetworkAdapter @p
  }

  if ($Generation -eq 2) {
    switch ($OS) {
      'Windows' { Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows }
      'Linux'   { Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority }
      'BSD'     { Set-VMFirmware -VMName $Name -EnableSecureBoot Off }
    }
    if ($Tpm) { Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector; Enable-VMTPM -VMName $Name }
  } elseif ($Tpm) { Write-Warning "${Name}: vTPM needs a Generation 2 VM - ignored." }
  Enable-VMIntegrationService -VMName $Name -Name 'Guest Service Interface'

  $dvd = Add-VMDvdDrive -VMName $Name -Passthru
  if ($Iso) { Set-VMDvdDrive -VMDvdDrive $dvd -Path $Iso } else { Write-Warning "${Name}: no ISO found - attach one before first boot." }
  if ($Generation -eq 2) { Set-VMFirmware -VMName $Name -FirstBootDevice (Get-VMDvdDrive -VMName $Name) }
  else { Set-VMBios -VMName $Name -StartupOrder @('CD', 'IDE', 'LegacyNetworkAdapter', 'Floppy') }

  # Verify, because an unbootable VM falls through to PXE with no explanation.
  $attached = (Get-VMDvdDrive -VMName $Name).Path
  if ($Iso -and $attached -ne $Iso) { Write-Warning "${Name}: ISO is NOT attached (path is '$attached'). Run: Set-VMDvdDrive -VMName $Name -Path '$Iso'" }
  if ($Generation -eq 2) {
    $fw = Get-VMFirmware -VMName $Name
    if ($fw.BootOrder[0].BootType -ne 'Drive') { Write-Warning "${Name}: first boot device is '$($fw.BootOrder[0].BootType)', not the DVD." }
    if ($OS -eq 'Linux' -and $fw.SecureBootTemplate -ne 'MicrosoftUEFICertificateAuthority') { Write-Warning "${Name}: Secure Boot template is '$($fw.SecureBootTemplate)'; Ubuntu needs MicrosoftUEFICertificateAuthority." }
  }
  Write-Host "Created $Name" -ForegroundColor Green
}
