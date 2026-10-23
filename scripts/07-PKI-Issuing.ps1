#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run INSIDE PKI-ISS (the enterprise issuing CA, domain-joined, on Lab-Admin).
           -Mode Prep    : set IP, join the domain, reboot.
           -Mode Request : install IIS and the CA role, publish the root, create the certificate request.
           -Mode Install : install the signed certificate and configure the issuing CA.
.NOTES     Request and Install must run as CORP\Administrator (publishing the root to AD needs Enterprise Admin).
           You are prompted for credentials when needed; nothing is stored.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Prep', 'Request', 'Install')][string]$Mode,
  [string]$DomainName = 'corp.lab.internal',
  [string]$CaName     = 'LAB-Issuing-CA',
  [string]$PkiHost    = 'pki.corp.lab.internal',
  [string]$Ip         = '10.50.0.12',
  [string]$Gateway    = '10.50.0.1',
  [string[]]$Dns      = @('10.50.0.10', '10.50.0.11')
)
$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'PKI-ISS') { throw "This script is for PKI-ISS (this is $env:COMPUTERNAME)." }

function Get-XferRoot {
  Get-Disk | Where-Object { $_.IsOffline -and $_.Size -lt 2GB } | ForEach-Object {
    Set-Disk -Number $_.Number -IsOffline $false; Set-Disk -Number $_.Number -IsReadOnly $false }
  $v = Get-Volume | Where-Object FileSystemLabel -eq 'PKI-XFER'
  if (-not $v) { throw 'Transfer disk (label PKI-XFER) not found. Attach it from the host with 05-Transfer-Disk.ps1.' }
  "$($v.DriveLetter):\"
}
function Set-XferOffline {
  Get-Disk | Where-Object { $_.Size -lt 2GB -and -not $_.IsBoot -and -not $_.IsSystem } | Set-Disk -IsOffline $true
}

switch ($Mode) {

  'Prep' {
    $nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    if (-not $nic) { throw 'No connected network adapter found.' }
    Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
    New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $Ip -PrefixLength 24 -DefaultGateway $Gateway | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $Dns
    $ok = $false
    for ($i = 1; $i -le 10 -and -not $ok; $i++) { $ok = [bool](ping.exe -n 1 -w 2000 $Dns[0] | Select-String 'TTL='); if (-not $ok) { Start-Sleep 3 } }
    if (-not $ok) { throw "Cannot reach DC01 at $($Dns[0])." }
    Add-Computer -DomainName $DomainName -Credential (Get-Credential -Message "Domain admin for $DomainName (CORP\Administrator)") -Restart
  }

  'Request' {
    $xfer = Get-XferRoot
    $root = Join-Path $xfer 'root'
    $rootCrt = Get-ChildItem $root -Filter *.crt | Select-Object -First 1
    if (-not $rootCrt) { throw "Root certificate not found in $root. Build the root CA first (06-PKI-Root.ps1 -Mode Build)." }

    # Web server that publishes the CRL and certificates at http://pki.<domain>/pki
    Install-WindowsFeature Web-Server, Web-Mgmt-Console, ADCS-Cert-Authority -IncludeManagementTools | Out-Null
    New-Item -ItemType Directory -Force C:\Pki | Out-Null
    Import-Module WebAdministration
    if (-not (Get-WebVirtualDirectory -Site 'Default Web Site' -Name pki -ErrorAction SilentlyContinue)) {
      New-WebVirtualDirectory -Site 'Default Web Site' -Name pki -PhysicalPath C:\Pki | Out-Null
    }
    & "$env:windir\system32\inetsrv\appcmd.exe" set config 'Default Web Site/pki' -section:system.webServer/security/requestFiltering -allowDoubleEscaping:true | Out-Null
    Set-WebConfigurationProperty -Filter /system.webServer/directoryBrowse -PSPath 'IIS:\Sites\Default Web Site\pki' -Name enabled -Value $true

    # DNS alias for the PKI web host, created on DC01
    Invoke-Command -ComputerName DC01 -ScriptBlock {
      param($zone, $alias)
      if (-not (Get-DnsServerResourceRecord -ZoneName $zone -Name pki -ErrorAction SilentlyContinue)) {
        Add-DnsServerResourceRecordCName -ZoneName $zone -Name pki -HostNameAlias $alias }
    } -ArgumentList $DomainName, "PKI-ISS.$DomainName"

    # Trust the root: publish to AD, add to the local store, and host it with its CRL
    certutil -dspublish -f $rootCrt.FullName RootCA | Out-Null
    certutil -addstore -f Root $rootCrt.FullName | Out-Null
    Copy-Item (Join-Path $root '*.crt'), (Join-Path $root '*.crl') C:\Pki -Force

    # Issuing CA: path length 0 so it can only issue end-entity certificates
    @'
[Version]
Signature="$Windows NT$"
[Certsrv_Server]
RenewalKeyLength=4096
RenewalValidityPeriod=Years
RenewalValidityPeriodUnits=10
[BasicConstraintsExtension]
PathLength=0
Critical=Yes
'@ | Set-Content C:\Windows\CAPolicy.inf -Encoding ASCII

    $reqDir = Join-Path $xfer 'request'; New-Item -ItemType Directory -Force $reqDir | Out-Null
    $reqFile = Join-Path $reqDir "$CaName.req"
    # This reports a warning that setup is incomplete until the signed certificate is installed. That is expected.
    Install-AdcsCertificationAuthority -CAType EnterpriseSubordinateCA -CACommonName $CaName `
      -KeyLength 4096 -HashAlgorithmName SHA256 -CryptoProviderName 'RSA#Microsoft Software Key Storage Provider' `
      -OutputCertRequestFile $reqFile -Force -WarningAction SilentlyContinue | Out-Null
    if (-not (Test-Path $reqFile)) { throw 'Certificate request was not created.' }
    Set-XferOffline
    Write-Host "Request written to $reqFile. Detach the transfer disk, attach it to PKI-ROOT, and run 06-PKI-Root.ps1 -Mode Sign." -ForegroundColor Green
  }

  'Install' {
    $xfer = Get-XferRoot
    $crt = Get-ChildItem (Join-Path $xfer 'signed') -Filter *.crt | Select-Object -First 1
    if (-not $crt) { throw "Signed certificate not found in ${xfer}signed. Sign the request on PKI-ROOT first." }
    Copy-Item (Join-Path $xfer 'root\*.crl') C:\Pki -Force       # refreshed root CRL
    certutil -f -installcert $crt.FullName | Out-Null
    Start-Service certsvc; Start-Sleep 5

    $win = 'C:\Windows\system32\CertSrv\CertEnroll'
    certutil -setreg CA\CRLPublicationURLs ("65:$win\%3%8%9.crl\n65:C:\Pki\%3%8%9.crl\n6:http://$PkiHost/pki/%3%8%9.crl") | Out-Null
    certutil -setreg CA\CACertPublicationURLs ("1:$win\%1_%3%4.crt\n1:C:\Pki\%1_%3%4.crt\n2:http://$PkiHost/pki/%1_%3%4.crt") | Out-Null
    certutil -setreg CA\CRLPeriod 'Weeks'  | Out-Null; certutil -setreg CA\CRLPeriodUnits 1      | Out-Null
    certutil -setreg CA\CRLDeltaPeriod 'Days' | Out-Null; certutil -setreg CA\CRLDeltaPeriodUnits 1 | Out-Null
    certutil -setreg CA\ValidityPeriod 'Years' | Out-Null; certutil -setreg CA\ValidityPeriodUnits 2 | Out-Null
    certutil -setreg CA\AuditFilter 127 | Out-Null
    Restart-Service certsvc; Start-Sleep 5
    certutil -crl | Out-Null
    Copy-Item "$win\*.crt" C:\Pki -Force -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Force 'C:\Lab\evidence' | Out-Null
    certutil -CAInfo   | Out-File 'C:\Lab\evidence\issuing-cainfo.txt'
    certutil -verify -urlfetch $crt.FullName | Out-File 'C:\Lab\evidence\issuing-chain-verify.txt'
    Set-XferOffline
    Write-Host 'Issuing CA is running. Check C:\Lab\evidence\issuing-chain-verify.txt (chain and CRL URLs should all verify).' -ForegroundColor Green
  }
}
