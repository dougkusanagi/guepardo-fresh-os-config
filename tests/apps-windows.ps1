$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../install.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Invalid installer syntax' }
foreach ($name in @('Get-InstallResult', 'Get-GuepardoCheckout', 'Install-SlothNote')) {
    $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    Invoke-Expression $function.Extent.Text
}
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$previousLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $sandbox
New-Item -ItemType Directory $sandbox | Out-Null
$script:dependencies = @()
function Install-RequiredWingetPackage { param($Id, $ExtraArgs) $script:dependencies += $Id }
function Write-Log { param($Message, $Level) }
function git {
    $global:LASTEXITCODE = 0
    if ($args -contains 'get-url') { return $script:origin }
    if ($args[0] -eq 'clone') { New-Item -ItemType Directory (Join-Path $args[-1] '.git') -Force | Out-Null }
}
try {
    $checkout = Get-GuepardoCheckout 'dougkusanagi/dotagents' 'dotagents'
    if ($checkout -isnot [string] -or -not (Test-Path (Join-Path $checkout '.git'))) { throw 'Checkout output is polluted or missing' }
    $script:origin = 'https://github.com/unrelated/repo.git'
    $rejected = $false
    try { Get-GuepardoCheckout 'dougkusanagi/dotagents' 'dotagents' } catch { $rejected = $true }
    if (-not $rejected) { throw 'Unexpected Git origin accepted' }
    $script:origin = 'https://github.com/dougkusanagi/dotagents.git'
    $null = Get-GuepardoCheckout 'dougkusanagi/dotagents' 'dotagents'
    # Release path runs downloaded installer once and propagates its failure.
    function Invoke-RestMethod { return @{ assets = @(@{ name='Sloth.Note_1.0_x64-setup.exe'; browser_download_url='https://example.test/sloth.exe' }) } }
    function Invoke-WebRequest { param($Uri, $OutFile, $TimeoutSec) Set-Content $OutFile 'mock installer' }
    $script:installerCode = 0
    $script:starts = 0
    function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru) $script:starts++; return @{ ExitCode=$script:installerCode } }
    Install-SlothNote
    if ($script:starts -ne 1) { throw 'Release installer was not run' }
    $script:installerCode = 1
    $rejected = $false
    try { Install-SlothNote } catch { $rejected = $true }
    if (-not $rejected) { throw 'Sloth Note installer failure was swallowed' }
    Write-Host 'Windows application installer checks passed'
} finally {
    $env:LOCALAPPDATA = $previousLocal
    Remove-Item $sandbox -Recurse -Force
}
