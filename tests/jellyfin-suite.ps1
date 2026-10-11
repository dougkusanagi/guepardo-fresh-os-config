#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$shell = (Get-Process -Id $PID).Path
foreach ($name in @('jellyfin.tests.ps1','jellyfin-plugins.tests.ps1','jellyfin-http.tests.ps1','jellyfin-banner.tests.ps1','jellyfin-restart.tests.ps1','jellyfin-integration.tests.ps1','windows-picker.tests.ps1')) {
    & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $name)
    if ($LASTEXITCODE -ne 0) { throw "Jellyfin test failed: $name" }
}
