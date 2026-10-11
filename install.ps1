<#
.SYNOPSIS
    Automated environment configuration installer for Windows.
.DESCRIPTION
    Installs dev stack, terminal tools, and desktop applications using Winget.
.PARAMETER Mode
    Installation scope: 'full' (dev + desktop + games), 'basic' (dev only), or 'games' (games only). Default: 'full'.
.PARAMETER DryRun
    Show what would be installed without making any changes.
.PARAMETER Help
    Show help message.
#>
[CmdletBinding()]
param (
    [ValidateSet('full', 'basic', 'games', 'server', 'desktop', 'wsl', 'jellyfin')]
    [string]$Mode = 'full',

    [string]$Profiles,

    [switch]$Plan,

    [switch]$ListProfiles,

    [switch]$DryRun,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($ListProfiles) {
    Write-Host "cli, dev, web, desktop, games, jellyfin"
    exit 0
}

if ($Help) {
    Write-Host @"
Usage:
  .\install.cmd
  .\install.ps1 [-Profiles cli,dev,web,desktop,games,jellyfin] [-Plan] [-DryRun]
  .\install.ps1 [-Mode <full|basic|games|server|desktop|wsl|jellyfin>]

Options:
  -Profiles Select independent profiles separated by commas.
  -Mode      Shortcut; full, basic, games, server, desktop, wsl, or jellyfin.
  -Plan      Show the package plan without changes.
  -ListProfiles List available profiles.
  -DryRun    Show what would be installed without making any changes.
  -Help      Show this help.
"@
    exit 0
}

# Keep logs in the user's data directory so running from a read-only archive
# or a temporary download does not break the installer.
$statePath = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrEmpty($statePath)) { $statePath = [IO.Path]::GetTempPath() }
$logDir = Join-Path $statePath "Guepardo/Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $logDir "install-$timestamp-$pid.log"

# Setup logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timeStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timeStr] [$Level] $Message"
    Add-Content -Path $logFile -Value $logLine

    switch ($Level) {
        "INFO" {
            Write-Host "-> $Message" -ForegroundColor Gray
        }
        "OK" {
            Write-Host "OK $Message" -ForegroundColor Green
        }
        "WARN" {
            Write-Host "WARN $Message" -ForegroundColor Yellow
        }
        "ERROR" {
            Write-Host "ERROR $Message" -ForegroundColor Red
        }
    }
}

function Write-Section {
    param ([string]$Title)
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    Write-Log -Message "=== Section: $Title ===" -Level "INFO"
}

# Ascii Art
function Show-Intro {
    Write-Host @'
   ______                                __    
  / ____/_  _____  ____  ____ __________/ /___ 
 / / __/ / / / _ \/ __ \/ __ `/ ___/ __  / __ \
/ /_/ / /_/ /  __/ /_/ / /_/ / /  / /_/ / /_/ /
\____/\__,_/\___/ .___/\__,_/_/   \__,_/\____/ 
               /_/                             
'@ -ForegroundColor Cyan

    Write-Host "Fresh Config Installer (Windows)" -ForegroundColor Green
    Write-Host "Target: Windows (via winget)" -ForegroundColor Yellow
    Write-Host "Profiles: $(if ($Profiles) { $Profiles } else { $Mode })" -ForegroundColor Yellow
    Write-Host "Log: $logFile`n" -ForegroundColor DarkGray
}

# Prompt if not explicitly set
$modeExplicitlySet = $PSBoundParameters.ContainsKey('Mode') -or $PSBoundParameters.ContainsKey('Profiles')
if (-not $modeExplicitlySet -and -not $Plan -and -not $DryRun -and [Environment]::UserInteractive) {
    . (Join-Path $PSScriptRoot 'modules/windows-picker.ps1')
    $Profiles = Select-WindowsProfiles
    if (-not $Profiles) {Write-Host 'Cancelado.'; exit 0}
}

Show-Intro

# Package groups are independent; selecting games does not pull in PHP or desktop apps.
$cliPackages = @(
    @{ Id = "GitHub.cli"; Name = "GitHub CLI" }
    @{ Id = "Git.Git"; Name = "Git" }
    @{ Id = "sharkdp.bat"; Name = "bat" }
    @{ Id = "Clement.bottom"; Name = "bottom" }
    @{ Id = "sharkdp.fd"; Name = "fd" }
    @{ Id = "junegunn.fzf"; Name = "fzf" }
    @{ Id = "BurntSushi.ripgrep.MSVC"; Name = "ripgrep" }
    @{ Id = "chmln.sd"; Name = "sd" }
    @{ Id = "dbrgn.tealdeer"; Name = "tealdeer" }
    @{ Id = "jqlang.jq"; Name = "jq" }
    @{ Id = "eza-community.eza"; Name = "eza" }
    @{ Id = "bootandy.dust"; Name = "dust" }
    @{ Id = "JesseDuffield.lazygit"; Name = "lazygit" }
    @{ Id = "sxyazi.yazi"; Name = "yazi" }
)
$devPackages = @(
    @{ Id = "Oven-sh.Bun"; Name = "Bun" }
    @{ Id = "astral-sh.uv"; Name = "uv" }
    @{ Id = "CoreyButler.NVMforWindows"; Name = "NVM for Windows" }
    @{ Id = "Google.AntigravityCLI"; Name = "Antigravity CLI"; Force = $true }
)
$webPackages = @(
    @{ Id = "PHP.PHP.8.4"; Name = "PHP" }
    @{ Id = "Composer.Composer"; Name = "Composer" }
    @{ Id = "Oracle.MySQL"; Name = "MySQL Server" }
)
$desktopPackages = @(
    @{ Id = "Warp.Warp"; Name = "Warp Terminal" }
    @{ Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code" }
    @{ Id = "ZedIndustries.Zed"; Name = "Zed Editor" }
    @{ Id = "Skillbrains.Lightshot"; Name = "Lightshot" }
    @{ Id = "Brave.Brave"; Name = "Brave Browser" }
    @{ Id = "Google.Chrome"; Name = "Google Chrome" }
    @{ Id = "Obsidian.Obsidian"; Name = "Obsidian" }
    @{ Id = "OBSProject.OBSStudio"; Name = "OBS Studio" }
    @{ Id = "ElementLabs.LMStudio"; Name = "LM Studio" }
    @{ Id = "RARLab.WinRAR"; Name = "WinRAR"; Force = $true }
    @{ Id = "Zen-Team.Zen-Browser"; Name = "Zen Browser" }
    @{ Id = "dynobo.NormCap"; Name = "NormCap" }
    @{ Id = "RedHat.Podman-Desktop"; Name = "Podman Desktop" }
    @{ Id = "VideoLAN.VLC"; Name = "VLC Media Player" }
    @{ Id = "CodecGuide.K-LiteCodecPack.Standard"; Name = "K-Lite Codec Pack Standard" }
)
$gamingPackages = @(
    @{ Id = "Valve.Steam"; Name = "Steam" }
    @{ Id = "EpicGames.EpicGamesLauncher"; Name = "Epic Games Launcher" }
    @{ Id = "GOG.Galaxy"; Name = "GOG Galaxy" }
    @{ Id = "Discord.Discord"; Name = "Discord" }
    @{ Id = "qBittorrent.qBittorrent"; Name = "qBittorrent" }
    @{ Id = "Stremio.Stremio"; Name = "Stremio" }
    @{ Id = "HeroicGamesLauncher.HeroicGamesLauncher"; Name = "Heroic Games Launcher" }
)
$jellyfinPackages = @(@{ Id = 'Jellyfin.Server'; Name = 'Jellyfin Server' })

if ($Profiles -and $PSBoundParameters.ContainsKey('Mode')) {
    throw "Use -Profiles or -Mode, not both."
}
if (-not $Profiles) {
    $Profiles = switch ($Mode) {
        'full'    { 'cli,dev,web,desktop,games,jellyfin' }
        'basic'   { 'cli,dev,web' }
        'server'  { 'cli' }
        'wsl'     { 'cli,dev,web' }
        'desktop' { 'desktop' }
        'games'   { 'games' }
        'jellyfin' { 'jellyfin' }
    }
}
$selectedProfiles = @($Profiles.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$validProfiles = @('cli', 'dev', 'web', 'desktop', 'games', 'jellyfin')
foreach ($profileName in $selectedProfiles) {
    if ($profileName -notin $validProfiles) { throw "Unknown profile: $profileName" }
}
if ($selectedProfiles.Count -eq 0) { throw 'Select at least one profile.' }

$groups = @{
    cli = $cliPackages
    dev = $devPackages
    web = $webPackages
    desktop = $desktopPackages
    games = $gamingPackages
    jellyfin = $jellyfinPackages
}
$toInstall = @()
foreach ($profileName in $validProfiles) {
    if ($profileName -in $selectedProfiles) { $toInstall += $groups[$profileName] }
}
$seenPackages = @{}
$toInstall = @($toInstall | Where-Object {
    if ($seenPackages.ContainsKey($_.Id)) { $false }
    else { $seenPackages[$_.Id] = $true; $true }
})

if ($Plan -or $DryRun) {
    Write-Log "Installation plan for profiles: $($selectedProfiles -join ', ')" -Level "INFO"
    foreach ($pkg in $toInstall) {
        Write-Log -Message "  $($pkg.Name) ($($pkg.Id))" -Level "INFO"
    }
    if ('jellyfin' -in $selectedProfiles) {
        Write-Log -Message '  Jellyfin: aguardar assistente inicial; login de administrador; tema GlassFin/polish.css com backup.' -Level INFO
        Write-Log -Message '  Plugins: AniDB, AniList, AniSearch, Kitsu, Artwork, Cover Art Archive, File Transformation e Media Bar (pacotes compativeis).' -Level INFO
        Write-Log -Message '  Ao terminar: comando para reiniciar o servico Jellyfin e Ctrl+Shift+R no navegador.' -Level INFO
    }
    Write-Log -Message "Dry-run completed successfully." -Level "OK"
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log -Level "ERROR" -Message "winget is not installed. Please install App Installer from the Microsoft Store."
    exit 1
}

function Update-ProcessEnvironment {
    Write-Log -Message "Refreshing environment variables for the current session..." -Level "INFO"
    $userEnv = [System.Environment]::GetEnvironmentVariables("User")
    $machineEnv = [System.Environment]::GetEnvironmentVariables("Machine")

    $userEnv.Keys | ForEach-Object {
        [System.Environment]::SetEnvironmentVariable($_, $userEnv[$_], "Process")
    }
    $machineEnv.Keys | ForEach-Object {
        [System.Environment]::SetEnvironmentVariable($_, $machineEnv[$_], "Process")
    }
    
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$machinePath;$userPath"
}

Write-Section "Installing Applications via winget"
$failed = @()
function Get-InstallResult {
    param ([long]$ExitCode)
    # Native HRESULTs can arrive as either signed or unsigned integers.
    $normalized = $ExitCode -band 4294967295L
    switch ($normalized) {
        0 { 'installed' }
        2316632107 { 'already-installed' } # 0x8A15002B: update not applicable
        2316632161 { 'already-installed' } # 0x8A150061: package already installed
        2316632333 { 'already-installed' } # 0x8A15010D: installer reports already installed
        2316632329 { 'reboot-required' }   # 0x8A150109: reboot required to finish
        3010 { 'reboot-required' }        # Successful EXE/MSI requiring a reboot
        default { 'failed' }
    }
}
$rebootRequired = $false
$startedAt = Get-Date
$packageIndex = 0
$jellyfinResult = 'not-selected'

foreach ($pkg in $toInstall) {
    $packageIndex++
    Write-Log -Message "[$packageIndex/$($toInstall.Count)] Installing $($pkg.Name) ($($pkg.Id))..." -Level "INFO"
    
    $exitCode = 1
    if ($pkg.Id -eq "Composer.Composer") {
        # Refresh environment variables first to make sure PHP is in PATH
        Update-ProcessEnvironment
        
        try {
            Write-Log -Message "Downloading Composer installer..." -Level "INFO"
            if (-not (Get-Command php -ErrorAction SilentlyContinue)) { throw 'PHP is required to install Composer.' }
            $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir | Out-Null
            $tempPath = Join-Path $tempDir 'Composer-Setup.exe'
            Invoke-WebRequest -Uri "https://getcomposer.org/Composer-Setup.exe" -OutFile $tempPath -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
            
            Write-Log -Message "Running Composer installer..." -Level "INFO"
            $process = Start-Process -FilePath $tempPath -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES" -Wait -PassThru -NoNewWindow
            $exitCode = $process.ExitCode
        } catch {
            Write-Log -Message "Failed to download or run Composer installer: $_" -Level "WARN"
            $exitCode = 1
        } finally {
            if ($tempDir -and (Test-Path $tempDir)) { Remove-Item -Path $tempDir -Recurse -Force }
        }
    } else {
        $argsList = @('install', '-e', '--id', $pkg.Id, '--source', 'winget', '--silent', '--disable-interactivity', '--no-upgrade', '--accept-package-agreements', '--accept-source-agreements')
        try {
            & winget @argsList 2>&1 | Tee-Object -FilePath $logFile -Append
            $exitCode = $LASTEXITCODE
        } catch {
            Write-Log -Message "Failed to run winget for $($pkg.Name): $_" -Level 'WARN'
            $exitCode = 1
        }
    }

    $result = Get-InstallResult $exitCode
    if ($pkg.Id -eq 'Jellyfin.Server') { $jellyfinResult = $result }
    if ($result -eq 'reboot-required') { $rebootRequired = $true }
    if ($result -ne 'failed') {
        Write-Log -Message "$($pkg.Name) installed/updated successfully (or already installed)." -Level "OK"
    } else {
        Write-Log -Message "Failed to install $($pkg.Name) (Exit Code: $exitCode)." -Level "WARN"
        $failed += $pkg.Name
    }
}

if ('jellyfin' -in $selectedProfiles) {
    Write-Section 'Configuring Jellyfin theme and plugins'
    if ($jellyfinResult -in @('installed','already-installed')) {
        try {
            # O servidor ja foi instalado acima; nao repete Winget nem loga credenciais.
            & (Join-Path $PSScriptRoot 'modules/jellyfin.ps1') -SkipInstall
            Write-Log -Message 'Jellyfin theme and plugin configuration completed.' -Level OK
        } catch {
            Write-Log -Message "Jellyfin configuration failed: $($_.Exception.Message)" -Level WARN
            $failed += 'Jellyfin configuration'
        }
    } elseif ($jellyfinResult -eq 'reboot-required') {
        Write-Log -Message 'Restart Windows, then run install.cmd -Profiles jellyfin to apply the theme and plugins.' -Level WARN
        $failed += 'Jellyfin configuration (Windows restart pending)'
    } else {
        Write-Log -Message 'Jellyfin configuration skipped because the server installation failed.' -Level WARN
    }
}

if ('cli' -in $selectedProfiles -or 'dev' -in $selectedProfiles -or 'web' -in $selectedProfiles) {
Write-Section "Configuring PowerShell Profile"
$profileDir = Split-Path -Path $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

if ('cli' -in $selectedProfiles) {
$profileContent = @'

# region Guepardo Fresh OS Config Shortcuts
function refreshenv {
    $userEnv = [System.Environment]::GetEnvironmentVariables("User")
    $machineEnv = [System.Environment]::GetEnvironmentVariables("Machine")
    $userEnv.Keys | ForEach-Object { [System.Environment]::SetEnvironmentVariable($_, $userEnv[$_], "Process") }
    $machineEnv.Keys | ForEach-Object { [System.Environment]::SetEnvironmentVariable($_, $machineEnv[$_], "Process") }
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = "$machinePath;$userPath"
    Write-Host "Environment variables refreshed!" -ForegroundColor Green
}

if (Get-Alias ls -ErrorAction SilentlyContinue) {
    Remove-Item alias:ls -Force
}
function ls { eza @args }
function l { eza -l @args }
# endregion
'@

$existingContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
if ([string]::IsNullOrEmpty($existingContent) -or $existingContent -notlike "*# region Guepardo Fresh OS Config Shortcuts*") {
    Add-Content -Path $PROFILE -Value $profileContent
    Write-Log -Message "Shortcuts added to PowerShell profile at $PROFILE." -Level "OK"
    Write-Host "-> To apply shortcuts in the current session, run: . `$PROFILE" -ForegroundColor Cyan
} else {
    Write-Log -Message "Shortcuts already exist in PowerShell profile." -Level "OK"
}
}

if ('dev' -in $selectedProfiles -and (Get-Content -Path $PROFILE -Raw) -notlike '*# region Guepardo Dev Shortcuts*') {
    Add-Content -Path $PROFILE -Value "`n# region Guepardo Dev Shortcuts`nfunction docker { podman @args }`nfunction docker-compose { podman compose @args }`n# endregion`n"
}
if ('web' -in $selectedProfiles -and (Get-Content -Path $PROFILE -Raw) -notlike '*# region Guepardo Web Shortcuts*') {
    Add-Content -Path $PROFILE -Value "`n# region Guepardo Web Shortcuts`nfunction a { php artisan @args }`n# endregion`n"
}

}

Write-Section "Installation Summary"
$elapsed = (Get-Date) - $startedAt
Write-Log -Message "Completed $($toInstall.Count) packages in $([math]::Round($elapsed.TotalMinutes, 1)) min. Log: $logFile" -Level "INFO"
if ($failed.Count -eq 0) {
    Write-Log -Message "All requested applications installed successfully!" -Level "OK"
} else {
    Write-Log -Message "Installation finished with warnings. The following apps failed to install:`n  $($failed -join ', ')" -Level "WARN"
    Write-Log -Message 'Fix the errors and repeat the same command; installed apps are reused.' -Level 'INFO'
}
if ($rebootRequired) { Write-Log -Message 'Restart Windows to finish installing the applications.' -Level 'WARN' }
if ($failed.Count -gt 0) { exit 1 }
exit 0
