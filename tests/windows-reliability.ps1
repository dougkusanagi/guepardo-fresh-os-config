$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '../install.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'PowerShell syntax errors' }

# Load only the result classifier, without running the installer.
$function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-InstallResult' }, $true)
Invoke-Expression $function.Extent.Text
foreach ($code in @(0, -1978335189, 2316632107, -1978335135, 2316632161, -1978334963, 2316632333)) {
    if ((Get-InstallResult $code) -eq 'failed') { throw "Success/no-op code rejected: $code" }
}
foreach ($code in @(-1978335204, 2316632092, -1978335203, 2316632093, -1978335186, 2316632110, 2316697643, 1)) {
    if ((Get-InstallResult $code) -ne 'failed') { throw "Failure reported as success: $code" }
}
if ((Get-InstallResult 3010) -ne 'reboot-required') { throw 'EXE restart code was lost' }
if ((Get-InstallResult -1978334967) -ne 'reboot-required') { throw 'Winget restart code was lost' }

# Run a child PowerShell with a fake Winget; isolate HOME/profile writes and
# environment refresh. No real app or Windows setting is touched.
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $sandbox | Out-Null
try {
    $driver = Join-Path $sandbox 'driver.ps1'
    @'
param([string]$Installer, [string]$Sandbox, [int]$FakeExitCode)
$PROFILE = Join-Path $Sandbox 'profile.ps1'
$global:GuepardoFakeExitCode = $FakeExitCode
function winget {
    $args -join ' ' | Add-Content (Join-Path $Sandbox 'calls')
    Write-Output 'Fake Winget diagnostic'
    $global:LASTEXITCODE = $global:GuepardoFakeExitCode
}
& $Installer -Profiles cli
exit $LASTEXITCODE
'@ | Set-Content $driver
    $pwsh = (Get-Process -Id $PID).Path
    foreach ($case in @(@{ Code = 0; Expected = 0 }, @{ Code = -1978335189; Expected = 0 }, @{ Code = -1978335186; Expected = 1 })) {
        $output = & $pwsh -NoLogo -NoProfile -File $driver -Installer $installer -Sandbox $sandbox -FakeExitCode $case.Code 2>&1 | Out-String
        if ($LASTEXITCODE -ne $case.Expected) { throw "Unexpected installer exit for $($case.Code): $LASTEXITCODE`n$output" }
        if ($case.Expected -eq 1 -and $output -notlike '*following apps failed*') { throw 'Failure summary missing' }
        if ($case.Expected -eq 1 -and $output -like '*All requested applications installed successfully*') { throw 'False success banner' }
    }
    $calls = Get-Content (Join-Path $sandbox 'calls')
    if (@($calls | Where-Object { $_ -notlike '*--silent*--disable-interactivity*--no-upgrade*' }).Count) { throw 'Winget can prompt or unnecessarily upgrade apps' }
    if (@($calls | Where-Object { $_ -notlike '*--source winget*' }).Count) { throw 'Winget source is ambiguous' }
    if (@($calls | Where-Object { $_ -like '*--force*' }).Count) { throw 'Installed apps were forced to reinstall' }
    Write-Host 'Windows reliability checks passed'
} finally {
    Remove-Item $sandbox -Recurse -Force
}
