#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('guepardo-jellyfin-' + [Guid]::NewGuid().ToString('N'))
$modulesDir = Join-Path $sandbox 'modules'
New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
$shell = (Get-Process -Id $PID).Path
try {
    Copy-Item -LiteralPath (Join-Path $root 'install.ps1') -Destination (Join-Path $sandbox 'install.ps1')
    @'
param([switch]$SkipInstall)
if (-not $SkipInstall) { throw 'Integration must skip duplicate Winget installation' }
Add-Content (Join-Path $PSScriptRoot '../module-calls') 'configured'
if ($env:GUEPARDO_TEST_MODULE_FAIL -eq '1') { throw 'Simulated Jellyfin configuration failure' }
'@ | Set-Content (Join-Path $modulesDir 'jellyfin.ps1')
    @'
param([string]$Installer,[int]$FakeExitCode,[string]$FailModule)
$env:GUEPARDO_TEST_MODULE_FAIL=$FailModule
$global:fakeExitCode=$FakeExitCode
function winget { $global:LASTEXITCODE=$global:fakeExitCode }
& $Installer -Profiles jellyfin
exit $LASTEXITCODE
'@ | Set-Content (Join-Path $sandbox 'driver.ps1')
    foreach ($case in @(@{Code=0;Fail='0';Expected=0;Calls=1},@{Code=-1978335189;Fail='0';Expected=0;Calls=2},@{Code=1;Fail='0';Expected=1;Calls=2},@{Code=3010;Fail='0';Expected=1;Calls=2},@{Code=0;Fail='1';Expected=1;Calls=3})) {
        $output = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sandbox 'driver.ps1') -Installer (Join-Path $sandbox 'install.ps1') -FakeExitCode $case.Code -FailModule $case.Fail 2>&1 | Out-String
        if ($LASTEXITCODE -ne $case.Expected) { throw "Unexpected exit code: $LASTEXITCODE`n$output" }
        $calls = @(Get-Content (Join-Path $sandbox 'module-calls'))
        if ($calls.Count -ne $case.Calls) { throw 'Jellyfin module ran despite failed installation or pending reboot' }
        if ($case.Fail -eq '1' -and $output -notlike '*Jellyfin configuration*') { throw 'Configuration failure missing from summary' }
    }
    Write-Host 'PASS: main installer invokes Jellyfin once, reuses apps, handles install/reboot/configuration failures.'
} finally {
    foreach ($file in @('modules/jellyfin.ps1','install.ps1','driver.ps1','module-calls')) {
        $path=Join-Path $sandbox $file
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
    }
    Remove-Item -LiteralPath $modulesDir
    Remove-Item -LiteralPath $sandbox
}
