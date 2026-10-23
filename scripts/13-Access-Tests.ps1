<#
.SYNOPSIS  Run INSIDE WS01 (as CORP\cui.user1) or WS02/WS03 (as CORP\corp.user1). Runs the boundary and
           access-control tests, prints PASS/FAIL against the expected result, and saves a transcript.
           Needs no admin rights. Output: C:\Users\Public\Documents\<host>-access-tests.txt
.EXAMPLE   powershell -ExecutionPolicy Bypass -File C:\Users\Public\Documents\13-Access-Tests.ps1
#>
$ErrorActionPreference = 'Continue'
$hostName = $env:COMPUTERNAME
Start-Transcript -Path "C:\Users\Public\Documents\$hostName-access-tests.txt" -Force | Out-Null

function Show-Result([string]$Test, [bool]$Expected, [bool]$Actual) {
  $verdict = if ($Expected -eq $Actual) { 'PASS' } else { 'FAIL' }
  $colour  = if ($verdict -eq 'PASS') { 'Green' } else { 'Red' }
  Write-Host ('{0}  {1}  (expected: {2}, got: {3})' -f $verdict, $Test, $(if ($Expected) { 'allowed' } else { 'denied' }), $(if ($Actual) { 'allowed' } else { 'denied' })) -ForegroundColor $colour
}
function Test-Tcp([string]$Target, [int]$Port) { [bool](Test-NetConnection $Target -Port $Port -WarningAction SilentlyContinue).TcpTestSucceeded }
# Treat any error inside the action as a denial (non-terminating errors included), and keep the error text short.
function Test-Can([scriptblock]$Action) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Stop'
  try { & $Action | Out-Null; $true }
  catch { Write-Host "    ($($_.Exception.Message))" -ForegroundColor DarkGray; $false }
  finally { $ErrorActionPreference = $old }
}

"Host: $hostName   User: $(whoami)   Time: $(Get-Date -Format s)"
"--- Groups ---"
whoami /groups | Select-String 'CUI|Corp'

if ($hostName -eq 'WS01') {                              # enclave workstation, expected user: CORP\cui.user1
  Show-Result 'Member of CUI-Users'                     $true  ([bool](whoami /groups | Select-String 'CUI-Users'))
  Show-Result 'Read \\FS01\CUI'                         $true  (Test-Can { Get-ChildItem '\\FS01\CUI' })
  $f = "\\FS01\CUI\Contracts\$($env:USERNAME)-test.txt"
  Show-Result 'Write a file to \\FS01\CUI\Contracts'    $true  (Test-Can { New-Item $f -ItemType File -Value 'access test' -Force })
  Show-Result 'Internet from the enclave (8.8.8.8:443)' $false (Test-Tcp '8.8.8.8' 443)
  Show-Result 'Corp workstation WS02 reachable (3389)'  $false (Test-Tcp '10.20.0.21' 3389)
} else {                                                 # Corp workstation, expected user: CORP\corp.user1
  Show-Result 'Member of CUI-Users'                     $false ([bool](whoami /groups | Select-String 'CUI-Users'))
  Show-Result 'Read \\FS01\CUI (permissions)'           $false (Test-Can { Get-ChildItem '\\FS01\CUI' })
  Show-Result 'RDP to FS01 (10.30.0.10:3389)'           $false (Test-Tcp '10.30.0.10' 3389)
  Show-Result 'SIEM dashboard (10.50.0.20:443)'         $false (Test-Tcp '10.50.0.20' 443)
  Show-Result 'Domain controller LDAP (10.50.0.10:389)' $true  (Test-Tcp '10.50.0.10' 389)
  Show-Result 'Internet web (1.1.1.1:443)'              $true  (Test-Tcp '1.1.1.1' 443)
}
Stop-Transcript | Out-Null
Write-Host "Saved: C:\Users\Public\Documents\$hostName-access-tests.txt" -ForegroundColor Cyan
