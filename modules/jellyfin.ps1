#requires -Version 5.1
<#
.SYNOPSIS
Instala Jellyfin e aplica o tema deste repositorio com backup do CSS anterior.
.EXAMPLE
.\modules\jellyfin.ps1
.EXAMPLE
.\modules\jellyfin.ps1 -SkipInstall -Credential (Get-Credential)
.EXAMPLE
.\modules\jellyfin.ps1 -Restore -Credential (Get-Credential)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ServerUrl = 'http://localhost:8096',
    [PSCredential]$Credential,
    [Security.SecureString]$ApiKey,
    [string]$CssPath,
    [string]$BackupDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WindowsFreshInstall/Jellyfin'),
    [switch]$SkipInstall,
    [switch]$SkipPlugins,
    [switch]$Restore,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 600
)

if (-not $CssPath) { $CssPath = Join-Path $PSScriptRoot '../jellyfin/polish.css' }

function Invoke-JellyfinRequest {
    param([string]$BaseUrl, [string]$Path, [string]$Method = 'GET', [hashtable]$Headers = @{}, $Body, [int]$RequestTimeout = 10)
    $request = @{
        Uri = "$BaseUrl/$Path"; Method = $Method; Headers = $Headers
        TimeoutSec = $RequestTimeout; ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 30 -Compress))
    }
    try {
        $response = Invoke-RestMethod @request
        # Invoke-RestMethod pode emitir um array JSON como um unico item do pipeline.
        # Enumerar aqui evita que o catalogo inteiro seja tratado como um plugin.
        return $response
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        $endpoint = ($Path -split '\?')[0]
        if ($status) {
            throw "Jellyfin: $Method $endpoint retornou HTTP $status."
        }
        throw "Jellyfin: nao foi possivel executar $Method $endpoint (conexao ou timeout)."
    }
}

function Set-JellyfinToken {
    param([hashtable]$Headers, [string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { throw 'Token do Jellyfin vazio.' }
    # Jellyfin 12 pode desabilitar X-Emby-Token; Authorization funciona sem auth legado.
    $Headers['Authorization'] = 'MediaBrowser Client="WindowsFreshInstall", Device="PowerShell", DeviceId="windows-fresh-install-jellyfin", Version="1.0.0", Token="' + [Uri]::EscapeDataString($Token) + '"'
}

function Show-JellyfinRestartInstructions {
    param([string]$BaseUrl)
    Write-Host 'Plugins instalados. Reinicie o Jellyfin para carrega-los.'
    if (([uri]$BaseUrl).IsLoopback) {
        $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'jellyfin' })
        if ($services.Count -eq 1) {
            $serviceName = $services[0].Name.Replace("'", "''")
            Write-Host 'Abra um PowerShell como administrador e execute:'
            Write-Host "  Restart-Service -Name '$serviceName'"
        } elseif ($services.Count -gt 1) {
            Write-Host 'Ha mais de um servico Jellyfin. No PowerShell como administrador, identifique o servico deste servidor:'
            Write-Host "  Get-Service -Name '*jellyfin*'"
            Write-Host "Depois execute Restart-Service -Name 'NOME_DO_SERVICO'."
        } else {
            Write-Host 'Nenhum servico Jellyfin encontrado. Feche e abra novamente o aplicativo Jellyfin.'
        }
    } else {
        Write-Host 'Reinicie o Jellyfin no computador que hospeda o servidor.'
    }
    Write-Host 'Quando o servidor voltar, pressione Ctrl+Shift+R no navegador para carregar o tema e o banner.'
}

function Install-JellyfinPlugins {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$ServerVersion,
        [string[]]$Required = @('AniDB', 'AniList', 'AniSearch', 'Kitsu', 'Artwork', 'Cover Art Archive'),
        [string]$Repository = 'https://repo.jellyfin.org/files/plugin/manifest.json')
    $parsedVersion = [version]$ServerVersion
    $ServerVersion = '{0}.{1}.{2}.{3}' -f $parsedVersion.Major, $parsedVersion.Minor, [Math]::Max(0,$parsedVersion.Build), [Math]::Max(0,$parsedVersion.Revision)
    $repositories = @(Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'Repositories' -Headers $Headers)
    if (-not ($repositories | Where-Object { $_.Url.TrimEnd('/') -eq $repository -and $_.Enabled })) {
        # Preserva repositorios existentes e habilita/adiciona apenas o oficial.
        $official = $repositories | Where-Object { $_.Url.TrimEnd('/') -eq $repository } | Select-Object -First 1
        if ($official) { $official.Enabled = $true }
        else { $repositories += [pscustomobject]@{ Name = 'Jellyfin Stable'; Url = $repository; Enabled = $true } }
        Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'Repositories' -Method POST -Headers $Headers -Body $repositories | Out-Null
    }
    $catalog = @(Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'Packages' -Headers $Headers -RequestTimeout 120)
    $installed = @(Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'Plugins' -Headers $Headers)
    $failures = @()
    $changed = $false
    foreach ($name in $required) {
        try {
            $package = $catalog | Where-Object { $_.Name -eq $name -and ($_.Versions | Where-Object { $_.RepositoryUrl -eq $repository }) } | Select-Object -First 1
            if (-not $package) { throw 'Nao encontrado no catalogo oficial.' }
            $versions = @($package.Versions | Where-Object {
                $_.RepositoryUrl -eq $repository -and
                (-not $_.TargetAbi -or [version]$_.TargetAbi -le [version]$ServerVersion)
            } | Sort-Object { [version]$_.Version } -Descending)
            if ($versions.Count -eq 0) { throw "Sem versao compativel com Jellyfin $ServerVersion no repositorio oficial." }
            $version = $versions[0].Version
            $packageId = $package.Guid
            if (-not $packageId) { throw 'Catalogo retornou plugin sem GUID.' }
            $existing = $installed | Where-Object { [guid]$_.Id -eq [guid]$packageId -and [version]$_.Version -ge [version]$version } | Select-Object -First 1
            if ($existing) {
                if ($existing.Status -in @('Disabled','NotSupported','Malfunctioned','Deleted')) {
                    throw "Ja instalado, mas com status $($existing.Status). Verifique no painel do Jellyfin."
                }
                Write-Host "$name ja instalado ($($existing.Version))."
                continue
            }
            $path = 'Packages/Installed/{0}?assemblyGuid={1}&version={2}&repositoryUrl={3}' -f
                [Uri]::EscapeDataString($name), [Uri]::EscapeDataString($packageId),
                [Uri]::EscapeDataString($version), [Uri]::EscapeDataString($repository)
            Write-Host "Instalando $name $version..."
            Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path $path -Method POST -Headers $Headers -RequestTimeout 300 | Out-Null
            # O endpoint aguarda o download, checksum e extracao antes de retornar.
            $changed = $true
        } catch {
            $failures += $name
            Write-Warning "$name : $($_.Exception.Message)"
        }
    }
    if ($changed) { Show-JellyfinRestartInstructions -BaseUrl $BaseUrl }
    if ($failures.Count) { throw "Falha ao instalar plugins: $($failures -join ', '). Corrija e execute novamente; plugins ja instalados serao reaproveitados." }
}

function Select-JellyfinBannerManifest {
    param($Manifest, [string]$ServerVersion)
    $server = [version]$ServerVersion
    foreach ($name in @('File Transformation','Media Bar')) {
        $package = $Manifest | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $package) { throw "Dependencia ausente no repositorio do banner: $name" }
        # O fornecedor publica varios ZIPs com o mesmo numero de versao.
        # A API escolhe o primeiro: filtrar por linha do servidor evita instalar o ZIP de 10.x em 12.x.
        $versions = @($package.Versions | Where-Object {
            $abi = [version]$_.TargetAbi
            $abi.Major -eq $server.Major -and $abi.Minor -eq $server.Minor -and
                $abi.Build -le [Math]::Max(0,$server.Build)
        } | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1)
        if (-not $versions.Count) { throw "Sem pacote de $name para Jellyfin $ServerVersion. Nenhuma versao de outra linha sera instalada." }
        $copy = $package | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $copy.Versions = $versions
        $copy
    }
}

function Install-JellyfinBanner {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$ServerVersion)
    if (-not ([uri]$BaseUrl).IsLoopback) {
        throw 'A instalacao automatica do banner requer executar o modulo no computador do Jellyfin usando localhost.'
    }
    $upstream = 'https://www.iamparadox.dev/jellyfin/plugins/manifest.json'
    $manifest = Invoke-RestMethod -Uri $upstream -TimeoutSec 60 -ErrorAction Stop
    $selected = @(Select-JellyfinBannerManifest -Manifest $manifest -ServerVersion $ServerVersion)
    $json = ConvertTo-Json -InputObject $selected -Depth 30 -Compress
    # Catalogo temporario somente em loopback. O Jellyfin continua responsavel
    # pelo download, checksum e instalacao. Nao altera arquivos do jellyfin-web.
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $feed = 'http://127.0.0.1:{0}/manifest.json' -f $listener.LocalEndpoint.Port
    $worker = [PowerShell]::Create()
    $worker.AddScript({
        param($Listener, $Json)
        $bytes = [Text.Encoding]::UTF8.GetBytes($Json)
        while ($true) {
            $client = $Listener.AcceptTcpClient()
            try {
                $client.ReceiveTimeout = 5000
                $client.SendTimeout = 5000
                $stream = $client.GetStream()
                $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
                try {
                    do { $line = $reader.ReadLine() } while ($null -ne $line -and $line.Length)
                    $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
                    $stream.Write($header,0,$header.Length)
                    $stream.Write($bytes,0,$bytes.Length)
                    $stream.Flush()
                } finally { $reader.Dispose() }
            } catch { } finally { $client.Dispose() }
        }
    }).AddArgument($listener).AddArgument($json) | Out-Null
    $job = $worker.BeginInvoke()
    $original = $null
    $registered = $false
    try {
        $original = @(Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'Repositories' -Headers $Headers)
        # Prioridade do catalogo filtrado sobre possiveis repositorios ja existentes.
        $temporary = @([pscustomobject]@{Name='WindowsFreshInstall banner'; Url=$feed; Enabled=$true}) + $original
        $registered = $true
        Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'Repositories' -Method POST -Headers $Headers -Body $temporary | Out-Null
        Install-JellyfinPlugins -BaseUrl $BaseUrl -Headers $Headers -ServerVersion $ServerVersion -Required @('File Transformation','Media Bar') -Repository $feed
    } finally {
        try {
            if ($registered) {
                Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'Repositories' -Method POST -Headers $Headers -Body $original | Out-Null
            }
        } finally {
            $listener.Stop()
            $worker.Stop()
            $worker.Dispose()
        }
    }
}

function Install-JellyfinThemeDependencies {
    param([string]$BaseUrl, [hashtable]$Headers, [string]$ServerVersion)
    $failures = @()
    try { Install-JellyfinPlugins -BaseUrl $BaseUrl -Headers $Headers -ServerVersion $ServerVersion } catch { $failures += $_.Exception.Message }
    try { Install-JellyfinBanner -BaseUrl $BaseUrl -Headers $Headers -ServerVersion $ServerVersion } catch { $failures += $_.Exception.Message }
    if ($failures.Count) { throw ($failures -join "`n") }
}

function Wait-JellyfinServer {
    param([string]$BaseUrl, [int]$Timeout)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $openedWizard = $false
    $reportedWaiting = $false
    while ($timer.Elapsed.TotalSeconds -lt $Timeout) {
        $info = $null
        try { $info = Invoke-JellyfinRequest -BaseUrl $BaseUrl -Path 'System/Info/Public' } catch { }
        if ($null -ne $info) {
            if ($info.StartupWizardCompleted) { return $info }
            if (-not $openedWizard) {
                Write-Host 'Conclua a configuracao inicial no navegador. O tema sera aplicado em seguida.'
                Start-Process "$BaseUrl/web/"
                $openedWizard = $true
            }
        } elseif (-not $reportedWaiting) {
            Write-Host "Aguardando Jellyfin em $BaseUrl. Se necessario, abra Jellyfin pelo menu Iniciar."
            $reportedWaiting = $true
        }
        Start-Sleep -Seconds 2
    }
    throw "Jellyfin nao ficou pronto em $Timeout segundos. Inicie o servidor, conclua o assistente e repita com -SkipInstall."
}

function Invoke-JellyfinModule {
    param([System.Management.Automation.PSCmdlet]$Caller, [hashtable]$Options)
    $ErrorActionPreference = 'Stop'
    if ($Options.Credential -and $Options.ApiKey) { throw 'Use Credential ou ApiKey, nao ambos.' }
    $uri = $null
    if (-not [Uri]::TryCreate($Options.ServerUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'ServerUrl deve ser uma URL HTTP/HTTPS sem credenciais, query ou fragmento.'
    }
    if ($uri.Scheme -eq 'http' -and -not $uri.IsLoopback) {
        throw 'Para servidores remotos, use HTTPS para proteger a senha de administrador.'
    }
    $baseUrl = $Options.ServerUrl.TrimEnd('/')
    $css = $null
    if (-not $Options.Restore) {
        $css = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Options.CssPath).Path)
        if ([string]::IsNullOrWhiteSpace($css)) { throw 'O arquivo CSS esta vazio.' }
    }
    $action = 'Instalar Jellyfin e aplicar tema'
    if ($Options.SkipInstall) { $action = 'Aplicar tema do Jellyfin' }
    if ($Options.Restore) { $action = 'Restaurar CSS anterior do Jellyfin' }
    elseif (-not $Options.SkipPlugins) { $action += ' e instalar plugins de metadados, File Transformation e Media Bar' }
    if (-not $Caller.ShouldProcess($baseUrl, $action)) { return }

    if (-not $Options.SkipInstall -and -not $Options.Restore) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'Winget nao encontrado. Instale o App Installer da Microsoft Store.' }
        & winget install --id Jellyfin.Server --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        $result = $LASTEXITCODE
        # Winget: sucesso, ja instalado/sem atualizacao, reboot solicitado/necessario.
        if ($result -notin @(0, -1978335189, 3010, 1641, -1978334967, -1978334966, -1978334965)) {
            throw "Winget falhou (codigo $result). O tema nao foi aplicado."
        }
        if ($result -in @(3010,1641,-1978334967,-1978334966,-1978334965)) {
            throw 'A instalacao solicita reinicializacao. Reinicie e execute este modulo com -SkipInstall.'
        }
    }
    # O install.ps1 principal ja instala o pacote e usa -SkipInstall aqui.
    # Mesmo nesse caso, iniciar o servico local antes de aguardar a API.
    if ($uri.IsLoopback) {
        $service = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'jellyfin' } | Select-Object -First 1
        if ($service -and $service.Status -eq 'Stopped') {
            try { Start-Service -InputObject $service } catch { Write-Warning 'Inicie o servico Jellyfin como administrador ou abra o aplicativo pelo menu Iniciar.' }
        }
    }
    $info = Wait-JellyfinServer -BaseUrl $baseUrl -Timeout $Options.TimeoutSeconds
    if (-not $info.Id -or $info.Id -notmatch '^[a-zA-Z0-9_-]+$') { throw 'O servidor nao retornou um identificador valido.' }
    $headers = @{ Authorization = 'MediaBrowser Client="WindowsFreshInstall", Device="PowerShell", DeviceId="windows-fresh-install-jellyfin", Version="1.0.0"' }
    $login = $null
    if ($Options.ApiKey) {
        Set-JellyfinToken -Headers $headers -Token ([PSCredential]::new('api', $Options.ApiKey)).GetNetworkCredential().Password
    } else {
        $admin = $Options.Credential
        if (-not $admin) {
            Write-Host 'Login do JELLYFIN (conta criada no navegador; nao e a conta do Windows).'
            $username = Read-Host 'Usuario administrador do Jellyfin'
            if ([string]::IsNullOrWhiteSpace($username)) { throw 'Autenticacao cancelada.' }
            $password = Read-Host 'Senha do Jellyfin' -AsSecureString
            $admin = [PSCredential]::new($username, $password)
        }
        try {
            $login = Invoke-JellyfinRequest -BaseUrl $baseUrl -Path 'Users/AuthenticateByName' -Method POST -Headers $headers -Body @{
                Username = $admin.UserName; Pw = $admin.GetNetworkCredential().Password
            }
        } catch { throw "Falha no login do Jellyfin. $($_.Exception.Message)" }
        if (-not $login.AccessToken) { throw 'O Jellyfin nao retornou um token de autenticacao.' }
        Set-JellyfinToken -Headers $headers -Token $login.AccessToken
    }
    try {
        if ($login -and -not $login.User.Policy.IsAdministrator) { throw 'Use uma conta de administrador do Jellyfin.' }
        $branding = Invoke-JellyfinRequest -BaseUrl $baseUrl -Path 'System/Configuration/branding' -Headers $headers
        if ($null -eq $branding -or $branding -isnot [pscustomobject] -or
            -not ($branding.PSObject.Properties['CustomCss'] -or
                $branding.PSObject.Properties['SplashscreenEnabled'] -or
                $branding.PSObject.Properties['LoginDisclaimer'])) { throw 'Resposta de branding incompativel.' }
        # Jellyfin omite campos nulos do JSON. Sem tema configurado, CustomCss nao existe.
        if (-not $branding.PSObject.Properties['CustomCss']) {
            $branding | Add-Member -MemberType NoteProperty -Name CustomCss -Value $null
        }
        $backupPath = Join-Path $Options.BackupDirectory "$($info.Id).json"
        if ($Options.Restore) {
            if (-not (Test-Path -LiteralPath $backupPath)) { throw "Backup nao encontrado: $backupPath" }
            $backup = [IO.File]::ReadAllText($backupPath) | ConvertFrom-Json
            if ($backup.ServerId -ne $info.Id -or -not $backup.PSObject.Properties['CustomCss']) { throw 'Backup invalido para este servidor.' }
            $css = $backup.CustomCss
        }
        if ($branding.CustomCss -ceq $css) {
            Write-Host 'O CSS desejado ja esta aplicado.'
            if (-not $Options.Restore -and -not $Options.SkipPlugins) {
                Install-JellyfinThemeDependencies -BaseUrl $baseUrl -Headers $headers -ServerVersion $info.Version
            }
            return
        }
        if (-not $Options.Restore -and -not (Test-Path -LiteralPath $backupPath)) {
            New-Item -ItemType Directory -Path $Options.BackupDirectory -Force | Out-Null
            $backupJson = @{ ServerId = $info.Id; ServerUrl = $baseUrl; CustomCss = $branding.CustomCss; SavedAt = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 30
            # CreateNew preserva o primeiro backup mesmo se o modulo for reaplicado.
            $stream = [IO.File]::Open($backupPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
            try {
                $bytes = [Text.Encoding]::UTF8.GetBytes($backupJson)
                $stream.Write($bytes, 0, $bytes.Length)
            } finally { $stream.Dispose() }
        }
        $branding.CustomCss = $css
        Invoke-JellyfinRequest -BaseUrl $baseUrl -Path 'System/Configuration/branding' -Method POST -Headers $headers -Body $branding | Out-Null
        $verified = Invoke-JellyfinRequest -BaseUrl $baseUrl -Path 'System/Configuration/branding' -Headers $headers
        if ($verified.CustomCss -cne $css) { throw "O servidor nao confirmou o CSS. Backup: $backupPath" }
        Write-Host "CSS aplicado. Backup original: $backupPath"
        Write-Host "Abra $baseUrl/web/ e atualize a pagina para ver o resultado."
        if (-not $Options.Restore -and -not $Options.SkipPlugins) {
            Install-JellyfinThemeDependencies -BaseUrl $baseUrl -Headers $headers -ServerVersion $info.Version
        }
    } finally {
        # Fecha a sessao temporaria sem salvar senha ou token em disco.
        if ($login) {
            try { Invoke-JellyfinRequest -BaseUrl $baseUrl -Path 'Sessions/Logout' -Method POST -Headers $headers | Out-Null } catch { }
        }
        $headers.Clear()
        $login = $null
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-JellyfinModule -Caller $PSCmdlet -Options @{
        ServerUrl = $ServerUrl; Credential = $Credential; ApiKey = $ApiKey; CssPath = $CssPath
        BackupDirectory = $BackupDirectory; SkipInstall = $SkipInstall
        Restore = $Restore; SkipPlugins = $SkipPlugins; TimeoutSeconds = $TimeoutSeconds
    }
}
