[CmdletBinding()]
param (
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$InstallerArguments
)

$ErrorActionPreference = 'Stop'
$repoUrl = 'https://github.com/dougkusanagi/guepardo-fresh-os-config'
$ref = if ($env:GUEPARDO_REF) { $env:GUEPARDO_REF } else { 'dev' }
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('guepardo-source-' + [Guid]::NewGuid().ToString('N'))
$installHome = if ($env:GUEPARDO_INSTALL_HOME) { $env:GUEPARDO_INSTALL_HOME } else { Join-Path $env:LOCALAPPDATA 'Guepardo/bin' }
$previousGuepardoRoot = [Environment]::GetEnvironmentVariable('GUEPARDO_ROOT', 'Process')
$createdStage = $false

try {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'Winget não foi encontrado. Instale o App Installer da Microsoft Store e execute novamente.'
    }

    $go = Get-Command go.exe -ErrorAction SilentlyContinue
    $goExe = if ($go) { $go.Source } else { $null }
    if (-not $goExe) {
        Write-Host 'Instalando Go para compilar o instalador...'
        & $winget.Source install -e --id GoLang.Go --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
        $wingetCode = $LASTEXITCODE
        if ($wingetCode -notin @(0, -1978335189, -1978335135)) {
            throw "Winget não conseguiu instalar Go (código $wingetCode)."
        }

        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = "$machinePath;$userPath"
        $go = Get-Command go.exe -ErrorAction SilentlyContinue
        if (-not $go) {
            $goPath = Join-Path $env:ProgramFiles 'Go\bin\go.exe'
            if (Test-Path -LiteralPath $goPath) {
                $goExe = $goPath
            }
        } else {
            $goExe = $go.Source
        }
        if (-not $goExe) {
            throw 'Go foi instalado, mas não foi encontrado. Feche e reabra o terminal e execute novamente.'
        }
    }

    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    $createdStage = $true
    $archive = Join-Path $stageRoot 'repository.zip'
    $sourceDir = Join-Path $stageRoot 'repository'
    $encodedRef = [Uri]::EscapeDataString($ref)
    $archiveUrl = "$repoUrl/archive/refs/heads/$encodedRef.zip"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "Baixando $repoUrl (ref: $ref)..."
    Invoke-WebRequest -UseBasicParsing -Uri $archiveUrl -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $sourceDir -Force
    $checkout = Get-ChildItem -LiteralPath $sourceDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'go.mod') } | Select-Object -First 1
    if (-not $checkout) {
        throw 'O arquivo baixado não contém a raiz esperada do repositório Go.'
    }

    New-Item -ItemType Directory -Path $installHome -Force | Out-Null
    $executable = Join-Path $installHome 'guepardo.exe'
    Write-Host 'Compilando o instalador Windows...'
    Push-Location $checkout.FullName
    try {
        & $goExe build -o $executable ./cmd/guepardo
        if ($LASTEXITCODE -ne 0) {
            throw "A compilação do instalador falhou (código $LASTEXITCODE)."
        }
        $env:GUEPARDO_ROOT = $checkout.FullName
        & $executable @InstallerArguments
        $installerExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} catch {
    Write-Error $_
    $installerExitCode = 1
} finally {
    if ($null -eq $previousGuepardoRoot) {
        Remove-Item Env:GUEPARDO_ROOT -ErrorAction SilentlyContinue
    } else {
        $env:GUEPARDO_ROOT = $previousGuepardoRoot
    }
    if ($createdStage) {
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $resolvedStage = [IO.Path]::GetFullPath($stageRoot)
        if (-not $resolvedStage.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Pasta temporária fora do local esperado; não removida: $resolvedStage"
        }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $installerExitCode
