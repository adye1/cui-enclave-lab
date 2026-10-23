#Requires -RunAsAdministrator
<#
.SYNOPSIS  HOST script. Installs the Wazuh agent on lab Windows VMs over PowerShell Direct
           (Hyper-V VM bus), so it works even for VMs with no internet, such as the CUI enclave.
.EXAMPLE   .\09-Deploy-WazuhAgent.ps1 -VM DC01,DC02,PKI-ISS
.NOTES     Download the agent MSI yourself first (Wazuh dashboard > Deploy new agent > Windows) and
           save it in F:\Installers. Its version must not be newer than the manager's.
           You are prompted for CORP\Administrator credentials; nothing is stored.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$VM,
  [string]$Manager = '10.50.0.20',
  [string]$MsiPath
)
$ErrorActionPreference = 'Stop'

if (-not $MsiPath) {
  $MsiPath = Get-ChildItem 'F:\Installers' -Filter 'wazuh-agent*.msi' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $MsiPath -or -not (Test-Path $MsiPath)) { throw 'Agent MSI not found. Save wazuh-agent-<version>.msi in F:\Installers (or pass -MsiPath).' }
"Using $MsiPath"
"SHA256: $((Get-FileHash $MsiPath -Algorithm SHA256).Hash)"

$cred = Get-Credential -UserName 'CORP\Administrator' -Message 'Domain administrator for the lab VMs'

foreach ($name in $VM) {
  if ((Get-VM -Name $name).State -ne 'Running') { Write-Warning "$name is not running - skipping."; continue }
  $s = New-PSSession -VMName $name -Credential $cred
  try {
    Invoke-Command -Session $s { New-Item -ItemType Directory -Force 'C:\Lab' | Out-Null }
    $remoteMsi = 'C:\Lab\' + (Split-Path $MsiPath -Leaf)
    Copy-Item -ToSession $s -Path $MsiPath -Destination $remoteMsi -Force
    $result = Invoke-Command -Session $s -ArgumentList $remoteMsi, $Manager, $name {
      param($msi, $mgr, $agentName)
      $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
        '/i', "`"$msi`"", '/qn', "WAZUH_MANAGER=`"$mgr`"", "WAZUH_AGENT_NAME=`"$agentName`"")
      if ($p.ExitCode -ne 0) { return "msiexec exit code $($p.ExitCode)" }
      Start-Service WazuhSvc
      Start-Sleep 3
      "WazuhSvc: $((Get-Service WazuhSvc).Status)"
    }
    "{0,-9} {1}" -f $name, $result
  } finally { Remove-PSSession $s }
}
"Done. In the Wazuh dashboard, open Agents; each VM should appear as Active within a minute or two."
