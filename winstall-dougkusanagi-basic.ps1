# Legacy entry point: use the same catalog, recovery, verification and UI.
& (Join-Path $PSScriptRoot 'install.ps1') @args
exit $LASTEXITCODE
