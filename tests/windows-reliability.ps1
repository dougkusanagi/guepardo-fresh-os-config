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
$env:GUEPARDO_RUNTIME_HOST=(Get-Process -Id $PID).Path
function Start-GuepardoAdminSession { return $null }
function Stop-GuepardoAdminSession {}
$PROFILE = Join-Path $Sandbox 'profile.ps1'
$global:GuepardoFakeExitCode = $FakeExitCode
$testCatalog=Get-Content (Join-Path (Split-Path $Installer) 'catalog/apps.json') -Raw | ConvertFrom-Json
function Get-Command {
    param([string]$Name,$ErrorAction)
    if($Name -eq 'scoop') { return $null } # Never call the host's real package manager.
    foreach($app in $testCatalog.apps) {
        if($Name -in $app.windows.commands -and (Test-Path (Join-Path $Sandbox ($app.id+'.installed')))) { return @{Name=$Name;Source=(Join-Path $Sandbox $Name)} }
    }
    Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue
}
function winget {
    $args -join ' ' | Add-Content (Join-Path $Sandbox 'calls')
    if ($args[0] -eq 'list') {
        $id = $args[[array]::IndexOf($args,'--id')+1]
        if (Test-Path (Join-Path $Sandbox ($id + '.installed'))) { Write-Output "$id 1.0"; $global:LASTEXITCODE=0 }
        else { $global:LASTEXITCODE=1 }
        return
    }
    Write-Output 'Fake Winget diagnostic'
    $global:LASTEXITCODE = $global:GuepardoFakeExitCode
    if ($global:GuepardoFakeExitCode -in @(0,-1978335189)) { Set-Content (Join-Path $Sandbox ($args[[array]::IndexOf($args,'--id')+1] + '.installed')) 'installed' }
}
& $Installer -Profiles cli -Provider winget -NoPrefetch -StateDirectory (Join-Path $Sandbox "state-$FakeExitCode")
exit $LASTEXITCODE
'@ | Set-Content $driver
    $pwsh = (Get-Process -Id $PID).Path
    foreach ($case in @(@{ Code = 0; Expected = 0 }, @{ Code = -1978335189; Expected = 0 }, @{ Code = -1978335186; Expected = 1 })) {
        Get-ChildItem $sandbox -Filter *.installed | Remove-Item -Force
        $output = & $pwsh -NoLogo -NoProfile -File $driver -Installer $installer -Sandbox $sandbox -FakeExitCode $case.Code 2>&1 | Out-String
        if ($LASTEXITCODE -ne $case.Expected) { throw "Unexpected installer exit for $($case.Code): $LASTEXITCODE`n$output" }
        if ($case.Expected -eq 1 -and $output -notlike '*following apps failed*') { throw 'Failure summary missing' }
        if ($case.Expected -eq 1 -and $output -like '*All requested applications installed successfully*') { throw 'False success banner' }
    }
    $calls = @(Get-Content (Join-Path $sandbox 'calls') | Where-Object { $_ -like 'install *' })
    if (@($calls | Where-Object { $_ -notlike '*--silent*--disable-interactivity*--no-upgrade*' }).Count) { throw ('Winget can prompt or unnecessarily upgrade apps: ' + ($calls -join [Environment]::NewLine)) }
    if (@($calls | Where-Object { $_ -notlike '*--source winget*' }).Count) { throw 'Winget source is ambiguous' }
    if (@($calls | Where-Object { $_ -like '*--force*' }).Count) { throw 'Installed apps were forced to reinstall' }
    Write-Host 'Windows reliability checks passed'
} finally {
    Remove-Item $sandbox -Recurse -Force
}
# GitHub Actions invokes scripts via -Command and propagates LASTEXITCODE.
# The last child deliberately fails; successful assertions must reset that result.
exit 0
