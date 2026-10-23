#Requires -RunAsAdministrator
<#
.SYNOPSIS  HOST script. Pulls C:\Lab\evidence out of the lab VMs into F:\Evidence\<VM>\<timestamp>
           using PowerShell Direct (travels over the Hyper-V VM bus, not the network),
           then writes a SHA-256 manifest of everything under F:\Evidence.
.EXAMPLE   .\08-Collect-Evidence.ps1                       # DC01, DC02, PKI-ISS
.EXAMPLE   .\08-Collect-Evidence.ps1 -VM PKI-ROOT          # root must be powered on; shut it down afterwards
.NOTES     You are prompted for credentials (CORP\Administrator for domain VMs, local Administrator
           for PKI-ROOT). Nothing is stored.
#>
[CmdletBinding()]
param(
  [string[]]$VM = @('DC01', 'DC02', 'PKI-ISS'),
  [string]$Dest = 'F:\Evidence',
  [string[]]$ExtraFiles = @('C:\Users\Public\Documents\*-access-tests.txt')
)
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$domCred = $null; $rootCred = $null

foreach ($name in $VM) {
  $state = (Get-VM -Name $name).State
  if ($state -ne 'Running') { Write-Warning "$name is $state - skipping (start it first)."; continue }

  if ($name -eq 'PKI-ROOT') {
    if (-not $rootCred) { $rootCred = Get-Credential -UserName 'Administrator' -Message 'Local Administrator on PKI-ROOT' }
    $cred = $rootCred
  } else {
    if (-not $domCred) { $domCred = Get-Credential -UserName 'CORP\Administrator' -Message 'Domain administrator' }
    $cred = $domCred
  }

  $session = New-PSSession -VMName $name -Credential $cred
  try {
    $target = Join-Path $Dest "$name\$stamp"
    New-Item -ItemType Directory -Force $target | Out-Null
    if (Invoke-Command -Session $session { Test-Path 'C:\Lab\evidence' }) {
      Copy-Item -FromSession $session -Path 'C:\Lab\evidence\*' -Destination $target -Recurse -Force
    }
    # Per-user test transcripts written by 13-Access-Tests.ps1 (standard users cannot write to C:\Lab)
    foreach ($pattern in $ExtraFiles) {
      $found = Invoke-Command -Session $session -ArgumentList $pattern { param($p) Test-Path $p }
      if ($found) { Copy-Item -FromSession $session -Path $pattern -Destination $target -Force }
    }
    $count = (Get-ChildItem $target -Recurse -File).Count
    if ($count -eq 0) { Remove-Item $target -Force; Write-Warning "$name has no evidence files yet - skipped."; continue }
    "{0,-9} -> {1}  ({2} files)" -f $name, $target, $count
  } finally { Remove-PSSession $session }
}

# Integrity manifest over everything collected so far
$manifest = Join-Path $Dest "manifest-sha256-$stamp.csv"
Get-ChildItem $Dest -Recurse -File | Where-Object Name -notlike 'manifest-sha256-*' |
  Get-FileHash -Algorithm SHA256 | Select-Object Hash, @{ n = 'Path'; e = { $_.Path.Substring($Dest.Length).TrimStart('\') } } |
  Export-Csv $manifest -NoTypeInformation
"Manifest: $manifest"
