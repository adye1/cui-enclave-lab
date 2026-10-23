#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run INSIDE PKI-ROOT (offline, not domain-joined, no network).
           -Mode Build : create the standalone root CA and export its certificate and CRL to the transfer disk.
           -Mode Sign  : sign the issuing CA's request from the transfer disk and return the certificate.
#>
[CmdletBinding()]
param(
  [ValidateSet('Build', 'Sign')][string]$Mode = 'Build',
  [string]$CaName  = 'LAB-Root-CA',
  [string]$PkiHost = 'pki.corp.lab.internal'
)
$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'PKI-ROOT') { throw "This script is for PKI-ROOT (this is $env:COMPUTERNAME)." }

function Get-XferRoot {
  Get-Disk | Where-Object { $_.IsOffline -and $_.Size -lt 2GB } | ForEach-Object {
    Set-Disk -Number $_.Number -IsOffline $false; Set-Disk -Number $_.Number -IsReadOnly $false }
  $v = Get-Volume | Where-Object FileSystemLabel -eq 'PKI-XFER'
  if (-not $v) { throw 'Transfer disk (label PKI-XFER) not found. Attach it from the host with 05-Transfer-Disk.ps1.' }
  "$($v.DriveLetter):\"
}
function Set-XferOffline {   # flushes and releases the disk so the host can detach it cleanly
  Get-Disk | Where-Object { $_.Size -lt 2GB -and -not $_.IsBoot -and -not $_.IsSystem } | Set-Disk -IsOffline $true
}

if ($Mode -eq 'Build') {
  # CA setup writes to its own CertConfig share over SMB loopback, which fails with no network adapter at all.
  if (-not (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {
    throw 'No connected network adapter. Attach a NIC on the isolated Lab-Isolated switch (host: Add-VMNetworkAdapter -VMName PKI-ROOT -SwitchName Lab-Isolated) and wait for it to connect.'
  }
  $xfer = Get-XferRoot
  Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools | Out-Null
  # Safe to rerun: skip the install if this CA is already configured.
  $caReg = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$CaName"
  if ((Test-Path $caReg) -and -not (Test-Path 'C:\Windows\system32\CertSrv\CertEnroll')) {
    throw "A half-configured CA '$CaName' exists (no CertEnroll folder). Run 'Uninstall-AdcsCertificationAuthority -Force', reboot, then rerun this script."
  }
  if (Test-Path $caReg) {
    Write-Host "CA '$CaName' already configured - skipping install, continuing with settings and export." -ForegroundColor Yellow
    if ((Get-Service certsvc).Status -ne 'Running') { Start-Service certsvc; Start-Sleep 5 }
  } else {
    Install-AdcsCertificationAuthority -CAType StandaloneRootCa -CACommonName $CaName `
      -KeyLength 4096 -HashAlgorithmName SHA256 -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' `
      -ValidityPeriod Years -ValidityPeriodUnits 20 -Force | Out-Null
  }

  # Where clients find the root's CRL and certificate (served by the issuing CA's web server).
  $cdp = 'CA\CRLPublicationURLs'; $aia = 'CA\CACertPublicationURLs'
  certutil -setreg $cdp ('1:C:\Windows\system32\CertSrv\CertEnroll\%3%8.crl\n2:http://' + $PkiHost + '/pki/%3%8.crl') | Out-Null
  certutil -setreg $aia ('1:C:\Windows\system32\CertSrv\CertEnroll\%1_%3%4.crt\n2:http://' + $PkiHost + '/pki/%1_%3%4.crt') | Out-Null
  certutil -setreg CA\CRLPeriod 'Weeks'      | Out-Null; certutil -setreg CA\CRLPeriodUnits 26    | Out-Null
  certutil -setreg CA\CRLOverlapPeriod 'Weeks' | Out-Null; certutil -setreg CA\CRLOverlapUnits 2   | Out-Null
  certutil -setreg CA\ValidityPeriod 'Years'  | Out-Null; certutil -setreg CA\ValidityPeriodUnits 10 | Out-Null
  certutil -setreg CA\AuditFilter 127         | Out-Null
  Restart-Service certsvc; Start-Sleep 5
  certutil -crl | Out-Null

  $out = Join-Path $xfer 'root'; New-Item -ItemType Directory -Force $out | Out-Null
  Copy-Item 'C:\Windows\system32\CertSrv\CertEnroll\*.crt', 'C:\Windows\system32\CertSrv\CertEnroll\*.crl' $out -Force
  New-Item -ItemType Directory -Force 'C:\Lab\evidence' | Out-Null
  certutil -CAInfo | Out-File 'C:\Lab\evidence\root-cainfo.txt'
  Copy-Item 'C:\Lab\evidence\root-cainfo.txt' $out -Force
  Set-XferOffline
  Write-Host "Root CA built. Root certificate and CRL are in ${out}. Detach the transfer disk from the host." -ForegroundColor Green
}

if ($Mode -eq 'Sign') {
  $xfer = Get-XferRoot
  $req = Get-ChildItem (Join-Path $xfer 'request') -Filter *.req | Select-Object -First 1
  if (-not $req) { throw "No request file found in ${xfer}request." }
  $config = "$env:COMPUTERNAME\$CaName"
  $sub = certreq -config $config -submit $req.FullName 2>&1 | Out-String
  if ($sub -notmatch 'RequestId:\s*(\d+)') { throw "Could not read a RequestId from certreq output:`n$sub" }
  $id = $Matches[1]
  certutil -config $config -resubmit $id | Out-Null            # issue the pending request
  $outDir = Join-Path $xfer 'signed'; New-Item -ItemType Directory -Force $outDir | Out-Null
  $crt = Join-Path $outDir ([IO.Path]::GetFileNameWithoutExtension($req.Name) + '.crt')
  certreq -config $config -retrieve $id $crt | Out-Null
  if (-not (Test-Path $crt)) { throw 'Certificate was not issued.' }
  certutil -crl | Out-Null
  Copy-Item 'C:\Windows\system32\CertSrv\CertEnroll\*.crl' (Join-Path $xfer 'root') -Force
  certutil -view -restrict "RequestId=$id" -out 'RequestId,CommonName,NotBefore,NotAfter' | Out-File 'C:\Lab\evidence\root-issued-subca.txt'
  Set-XferOffline
  Write-Host "Issued request $id -> $crt. Shut PKI-ROOT down when finished." -ForegroundColor Green
}
