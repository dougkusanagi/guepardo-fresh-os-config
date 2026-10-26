[CmdletBinding()]
param([switch]$AllShells)
$ErrorActionPreference='Stop'
$shells=@((Get-Process -Id $PID).Path)
if($AllShells -and $env:OS -eq 'Windows_NT') {
    foreach($name in @('pwsh','powershell.exe')) {
        $command=Get-Command $name -ErrorAction SilentlyContinue
        if($command -and $command.Source -notin $shells) { $shells+=$command.Source }
    }
}
$suites=@('test-windows.ps1','windows-reliability.ps1','apps-windows.ps1','installer-engine.tests.ps1','environment.tests.ps1','msys-bridge.tests.ps1','keyboard-picker.tests.ps1','download-http.tests.ps1','installer-integration.tests.ps1','jellyfin-suite.ps1','runtime.tests.ps1','elevation.tests.ps1','powershell-wsl.tests.ps1','jellyfin-state.tests.ps1','manage.tests.ps1','msvc.tests.ps1')
foreach($shell in $shells) {
    foreach($suite in $suites) {
        # The application and admin worker run under PowerShell 7 after bootstrap.
        # Keep PS5 coverage for bootstrap/modules; run orchestration in its actual host.
        $suiteShell=$shell
        if ([IO.Path]::GetFileName($shell) -eq 'powershell.exe' -and $suite -in @('windows-reliability.ps1','installer-integration.tests.ps1','elevation.tests.ps1')) { $suiteShell=(Get-Command pwsh -ErrorAction Stop).Source }
        $output=& $suiteShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $suite) 2>&1 | Out-String
        if($LASTEXITCODE -ne 0) { throw "$shell / $suite failed:`n$output" }
        Write-Host "PASS $([IO.Path]::GetFileName($shell)) / $suite"
    }
}
Write-Host "PASS $($suites.Count * $shells.Count) suite executions; no real app was installed."
exit 0
