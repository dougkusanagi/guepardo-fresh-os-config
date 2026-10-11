#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'modules/jellyfin.ps1')

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('jellyfin-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$cssFile = Join-Path $temp 'theme.css'
[IO.File]::WriteAllText($cssFile, '/* acento */ body { color: purple; }')
$script:state = [pscustomobject]@{ CustomCss = 'original'; LoginDisclaimer = 'preservar'; SplashscreenEnabled = $true }
$script:posts = 0
$script:requests = 0
$script:adminAllowed = $true
$script:installCalls = 0
$script:wingetResult = -1978335189
$script:authCalls = 0
$script:logoutCalls = 0
$script:pluginCalls = 0

function winget { $script:installCalls++; $global:LASTEXITCODE = $script:wingetResult }
function Get-Service { return $null }
function Wait-JellyfinServer { return [pscustomobject]@{ Id = 'server123'; StartupWizardCompleted = $true } }
function Invoke-JellyfinRequest {
    param($BaseUrl, $Path, $Method = 'GET', $Headers, $Body)
    $script:requests++
    if ($Path -ne 'Users/AuthenticateByName') {
        # Reproduz Jellyfin 12 com EnableLegacyAuthorization desabilitado:
        # nao aceita X-Emby-Token; exige Token dentro de Authorization.
        if ($Headers.Authorization -notmatch 'Token="(test|fake-key)"' -or $Headers.ContainsKey('X-Emby-Token')) {
            throw 'HTTP 401: token ausente no Authorization'
        }
    }
    switch ($Path) {
        'Users/AuthenticateByName' { $script:authCalls++; return [pscustomobject]@{ AccessToken = 'test'; User = [pscustomobject]@{ Policy = [pscustomobject]@{ IsAdministrator = $script:adminAllowed } } } }
        'System/Configuration/branding' {
            if ($Method -eq 'POST') {
                $script:posts++
                $script:state = $Body | ConvertTo-Json | ConvertFrom-Json
                return
            }
            return ($script:state | ConvertTo-Json | ConvertFrom-Json)
        }
        'Sessions/Logout' { $script:logoutCalls++; return }
        default { throw "Unexpected endpoint $Path" }
    }
}
function Install-JellyfinThemeDependencies { $script:pluginCalls++ }
function Run-Module {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Restore, [switch]$Install, [switch]$UseApiKey, [switch]$Plugins, [string]$Url = 'http://localhost:8096')
    $credential = [PSCredential]::new('admin', (ConvertTo-SecureString 'fake' -AsPlainText -Force))
    $key = $null
    if ($UseApiKey) { $credential = $null; $key = ConvertTo-SecureString 'fake-key' -AsPlainText -Force }
    Invoke-JellyfinModule -Caller $PSCmdlet -Options @{
        ServerUrl = $Url; Credential = $credential; ApiKey = $key
        CssPath = $cssFile; BackupDirectory = $temp; SkipInstall = -not $Install
        Restore = $Restore; SkipPlugins = -not $Plugins; TimeoutSeconds = 1
    }
}
try {
    Run-Module -WhatIf -Install
    Assert ($script:requests -eq 0 -and $script:installCalls -eq 0) 'WhatIf nao chama API nem Winget'
    Run-Module -Install
    Assert ($script:installCalls -eq 1) 'Winget ja instalado permite continuar'
    Assert ($script:state.CustomCss -eq [IO.File]::ReadAllText($cssFile)) 'aplica CSS'
    Assert ($script:state.LoginDisclaimer -eq 'preservar' -and $script:state.SplashscreenEnabled) 'preserva branding'
    $backupFile = Join-Path $temp 'server123.json'
    $backupText = [IO.File]::ReadAllText($backupFile)
    Assert (($backupText | ConvertFrom-Json).CustomCss -eq 'original') 'backup do CSS original'
    Run-Module
    Assert ($script:posts -eq 1) 'reaplicacao nao grava novamente'
    Assert ([IO.File]::ReadAllText($backupFile) -ceq $backupText) 'preserva primeiro backup'
    $script:state.LoginDisclaimer = 'alterado depois'
    Run-Module -Restore
    Assert ($script:state.CustomCss -eq 'original') 'restaura CSS'
    Assert ($script:state.LoginDisclaimer -eq 'alterado depois') 'restore preserva branding atual'
    $script:adminAllowed = $false
    $failed = $false
    try { Run-Module } catch { $failed = $_.Exception.Message -like '*administrador*' }
    Assert $failed 'recusa conta sem permissao'
    Assert ($script:posts -eq 2) 'conta sem permissao nao altera tema'
    $failed = $false
    try { Run-Module -Url 'http://media.example.com' } catch { $failed = $_.Exception.Message -like '*HTTPS*' }
    Assert $failed 'recusa senha sobre HTTP remoto'
    $script:adminAllowed = $true
    $script:wingetResult = 1
    $previousRequests = $script:requests
    $failed = $false
    try { Run-Module -Install } catch { $failed = $_.Exception.Message -like '*Winget falhou*' }
    Assert ($failed -and $script:requests -eq $previousRequests) 'falha de instalacao nao chama API'
    [IO.File]::WriteAllText($backupFile, '{"ServerId":"other","CustomCss":"errado"}')
    $failed = $false
    try { Run-Module -Restore } catch { $failed = $_.Exception.Message -like '*Backup invalido*' }
    Assert ($failed -and $script:posts -eq 2) 'restore recusa backup de outro servidor'
    $previousAuth = $script:authCalls
    $previousLogout = $script:logoutCalls
    Run-Module -UseApiKey -Plugins
    Run-Module -UseApiKey -Plugins
    Assert ($script:authCalls -eq $previousAuth -and $script:logoutCalls -eq $previousLogout) 'chave API nao faz login nem encerra sessao do usuario'
    Assert ($script:pluginCalls -eq 2) 'plugins executam mesmo se CSS ja estiver aplicado'
    Remove-Item -LiteralPath $backupFile -Force
    # Resposta real de Jellyfin 12.1 novo: campos nulos sao omitidos do JSON.
    $script:state = [pscustomobject]@{ SplashscreenEnabled = $false }
    Run-Module -UseApiKey
    Assert ($script:state.CustomCss -eq [IO.File]::ReadAllText($cssFile)) 'aceita branding sem CustomCss'
    Assert ($script:state.SplashscreenEnabled -eq $false) 'preserva splash desabilitado'
    Assert ($null -eq ([IO.File]::ReadAllText($backupFile) | ConvertFrom-Json).CustomCss) 'backup preserva CSS nulo'
    Run-Module -UseApiKey -Restore
    Assert ($null -eq $script:state.CustomCss) 'restaura CSS nulo'
    Write-Host 'PASS: simulacao, instalacao, aplicacao, backup, idempotencia, restauracao e autenticacao.'
} finally {
    # Apenas arquivos conhecidos criados pelo teste; nenhuma exclusao recursiva.
    foreach ($path in @($cssFile, (Join-Path $temp 'server123.json'))) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    Remove-Item -LiteralPath $temp
}
