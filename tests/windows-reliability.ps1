$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$go = Get-Command go.exe -ErrorAction SilentlyContinue
if (-not $go) { throw 'Go 1.22+ is required for the Windows installer build check.' }

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$buildDir = Join-Path $tempRoot ('guepardo-windows-build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildDir | Out-Null
try {
    Push-Location $root
    try {
        $executable = Join-Path $buildDir 'guepardo.exe'
        & $go.Source build -o $executable ./cmd/guepardo
        if ($LASTEXITCODE -ne 0) { throw "Windows build failed ($LASTEXITCODE)." }
    } finally {
        Pop-Location
    }

    Push-Location $buildDir
    try {
        $plan = & $executable --profiles=full --plan 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "Compiled Windows plan failed:`n$plan" }
        foreach ($package in @('RevoUninstaller.RevoUninstaller','Oven-sh.Bun','astral-sh.uv','Jellyfin.Server')) {
            if ($plan -notlike "*$package*") { throw "Compiled plan is missing $package." }
        }
        if ($plan -notlike '*Sistema: Windows*' -or $plan -notlike '*Nenhum aplicativo ou configuração foi alterado*') {
            throw 'Compiled executable did not use the safe Windows plan.'
        }
        if ($plan -notlike '*WSL 2*' -or $plan -notlike '*Virtual Machine Platform*' -or $plan -notlike '*Ubuntu*') {
            throw 'Compiled Windows plan is missing the WSL 2 and Ubuntu setup.'
        }
    } finally {
        Pop-Location
    }
} finally {
    $resolvedBuild = [IO.Path]::GetFullPath($buildDir)
    if (-not $resolvedBuild.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Temporary build path is outside the temp directory; not removed: $resolvedBuild"
    }
    Remove-Item -LiteralPath $resolvedBuild -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'Windows reliability checks passed.'
