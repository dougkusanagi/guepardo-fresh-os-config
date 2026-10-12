# Windows installer tests
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$go = Get-Command go.exe -ErrorAction SilentlyContinue
if (-not $go) { throw 'Go 1.22+ is required for the Windows Go installer tests.' }

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'install.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { throw 'install.ps1 has PowerShell syntax errors.' }
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/bootstrap-windows.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { throw 'bootstrap-windows.ps1 has PowerShell syntax errors.' }

$launcher = Get-Content (Join-Path $root 'install.cmd') -Raw
if ($launcher -notlike '*go run ./cmd/guepardo*') { throw 'install.cmd must launch the Go installer.' }
$bootstrap = Get-Content (Join-Path $root 'scripts/bootstrap-windows.ps1') -Raw
if ($bootstrap -notlike '*github.com/dougkusanagi/guepardo-fresh-os-config*' -or $bootstrap -notlike '* build -o $executable ./cmd/guepardo*' -or $bootstrap -notlike '*GUEPARDO_INSTALL_HOME*') {
    throw 'OneDrive bootstrap must download this GitHub repository and compile the Go installer.'
}

Push-Location $root
try {
    & $go.Source test ./...
    if ($LASTEXITCODE -ne 0) { throw "Go tests failed ($LASTEXITCODE)." }

    $plan = & $go.Source run ./cmd/guepardo --profiles=full --plan 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Windows full plan failed:`n$plan" }
    foreach ($package in @(
        'RevoUninstaller.RevoUninstaller', 'Oven-sh.Bun', 'astral-sh.uv',
        'CoreyButler.NVMforWindows', 'GitHub.GitHubDesktop', 'T3Tools.T3Code',
        'Canva.Affinity', 'Comfy.ComfyUI-Desktop', 'Jellyfin.Server',
        'GnuPG.Gpg4win', 'wget', 'unzip', 'OpenAI.Codex', 'SST.opencode'
    )) {
        if ($plan -notlike "*$package*") { throw "Full Windows plan is missing $package." }
    }
    if ($plan -notlike '*scoop: wget*' -or $plan -notlike '*scoop: unzip*' -or $plan -notlike '*Node.js LTS e npm via NVM*') {
        throw 'Full Windows plan must show Scoop utilities and Node LTS setup.'
    }
    if ($plan -notlike '*WSL 2*' -or $plan -notlike '*Ubuntu*' -or $plan -notlike '*Virtual Machine Platform*') {
        throw 'Full Windows plan must include WSL 2, Virtual Machine Platform, and Ubuntu.'
    }
    if ($plan -notlike '*Nenhum aplicativo ou configuração foi alterado*') { throw 'Plan mode must not change the system.' }

    $desktop = & $go.Source run ./cmd/guepardo --profiles=desktop --plan 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $desktop -notlike '*RevoUninstaller.RevoUninstaller*' -or $desktop -like '*GitHub CLI*') {
        throw "Windows desktop profile is incorrect:`n$desktop"
    }

    $wsl = & $go.Source run ./cmd/guepardo --profiles=wsl2 --plan 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $wsl -notlike '*Ubuntu*' -or $wsl -notlike '*Nenhum aplicativo ou configuração foi alterado*') {
        throw "Windows WSL plan is incorrect:`n$wsl"
    }
} finally {
    Pop-Location
}

Write-Host 'Windows Go installer tests passed.' -ForegroundColor Green
