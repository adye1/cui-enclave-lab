#Requires -RunAsAdministrator
<#
.SYNOPSIS  Run INSIDE FS01 after it has joined the domain, logged in as CORP\Administrator.
           Creates the CUI file share with MOCK data only, locks down NTFS and SMB, turns on
           file-access auditing, and writes evidence to C:\Lab\evidence.
#>
[CmdletBinding()]
param([string]$Root = 'C:\Shares\CUI')
$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'FS01') { throw "This script is for FS01 (this is $env:COMPUTERNAME)." }

Install-WindowsFeature FS-FileServer | Out-Null

# --- Folders and clearly-labelled MOCK content --------------------------------
$folders = 'Contracts', 'Engineering', 'Program-Reports'
foreach ($f in $folders) { New-Item -ItemType Directory -Force (Join-Path $Root $f) | Out-Null }
foreach ($f in $folders) {
  1..3 | ForEach-Object {
    $path = Join-Path $Root "$f\SAMPLE-$f-$_.txt"
    "CUI//MOCK  -  SAMPLE DATA ONLY. Fictional content created for a security lab. Contains no real information.`r`nDocument: $f $_   Created: $(Get-Date -Format s)" |
      Set-Content $path
  }
}

# --- NTFS: remove inheritance, grant by group (domain groups from 04-AD-Structure.ps1) -------
icacls $Root /inheritance:r | Out-Null
icacls $Root /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' 'CORP\CUI-Admins:(OI)(CI)F' 'CORP\CUI-Users:(OI)(CI)M' | Out-Null

# --- SMB: signing and encryption required, SMB1 off ---------------------------
Set-SmbServerConfiguration -EnableSMB1Protocol $false -RequireSecuritySignature $true -EncryptData $true -Force
if (-not (Get-SmbShare -Name CUI -ErrorAction SilentlyContinue)) {
  New-SmbShare -Name CUI -Path $Root -FullAccess 'CORP\CUI-Admins' -ChangeAccess 'CORP\CUI-Users' -EncryptData $true | Out-Null
}

# --- Auditing: file access and logon events ------------------------------------
auditpol /set /subcategory:"File System"            /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"File Share"             /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Logon"                  /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Logoff"                 /success:enable                 | Out-Null
auditpol /set /subcategory:"Account Lockout"        /failure:enable                 | Out-Null
$acl = Get-Acl $Root
$rights = [System.Security.AccessControl.FileSystemRights]'Modify,Delete,ChangePermissions,TakeOwnership'
$rule = New-Object System.Security.AccessControl.FileSystemAuditRule('Everyone', $rights, 'ContainerInherit,ObjectInherit', 'None', 'Success,Failure')
$acl.AddAuditRule($rule); Set-Acl $Root $acl

# --- Evidence -------------------------------------------------------------------
$ev = 'C:\Lab\evidence'; New-Item -ItemType Directory -Force $ev | Out-Null
Get-SmbShare -Name CUI | Format-List * | Out-File "$ev\fs01-smbshare.txt"
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, RequireSecuritySignature, EncryptData | Format-List | Out-File "$ev\fs01-smbconfig.txt"
(Get-Acl $Root).Access | Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize | Out-File "$ev\fs01-ntfs-acl.txt"
auditpol /get /category:* | Out-File "$ev\fs01-auditpol.txt"
Write-Host "FS01 configured. Share \\FS01\CUI created with mock data. Evidence in $ev." -ForegroundColor Green
