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
    [ValidateSet('full', 'basic', 'games')]
    [string]$Mode = 'full',

    [switch]$DryRun,

    [switch]$Help
)

if ($Help) {
    Write-Host @"
Usage:
  .\install.ps1 [-Mode <full|basic|games>] [-DryRun] [-Help]

Options:
  -Mode      Installation scope: full (dev + desktop + games), basic (dev only), or games (gaming apps only). Default: full.
  -DryRun    Show what would be installed without making any changes.
  -Help      Show this help.
"@
    exit 0
}

# Determine paths
$rootPath = $PSScriptRoot
if ([string]::IsNullOrEmpty($rootPath)) {
    $rootPath = Get-Location
}
$logDir = Join-Path $rootPath "logs"
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

    Write-Host "Fresh Config Installer (Windows)" -ForegroundColor Green -BackgroundColor Black
    Write-Host "Target: Windows (via winget)" -ForegroundColor Yellow
    Write-Host "Mode: $Mode" -ForegroundColor Yellow
    Write-Host "Log: $logFile`n" -ForegroundColor DarkGray
}

# Prompt if not explicitly set
$modeExplicitlySet = $PSBoundParameters.ContainsKey('Mode')
if (-not $modeExplicitlySet -and [Environment]::UserInteractive) {
    $title = "Select Installation Mode"
    $message = "Choose the scope of the installation:"
    $full = New-Object System.Management.Automation.Host.ChoiceDescription "&Full", "Dev tools + Desktop apps + Games"
    $basic = New-Object System.Management.Automation.Host.ChoiceDescription "&Basic", "Dev tools only"
    $games = New-Object System.Management.Automation.Host.ChoiceDescription "&Games", "Gaming apps only"
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($full, $basic, $games)
    $decision = $Host.UI.PromptForChoice($title, $message, $choices, 0)
    
    switch ($decision) {
        0 { $Mode = 'full' }
        1 { $Mode = 'basic' }
        2 { $Mode = 'games' }
    }
}

Show-Intro

# Check for winget
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log -Level "ERROR" -Message "winget is not installed. Please install App Installer from the Microsoft Store."
    exit 1
}

# Packages definition
$basicPackages = @(
    # Core Dev Stack
    @{ Id = "Warp.Warp"; Name = "Warp Terminal" }
    @{ Id = "GitHub.cli"; Name = "GitHub CLI" }
    @{ Id = "Git.Git"; Name = "Git" }
    @{ Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code" }
    @{ Id = "ZedIndustries.Zed"; Name = "Zed Editor" }
    @{ Id = "Oven-sh.Bun"; Name = "Bun" }
    @{ Id = "astral-sh.uv"; Name = "uv" }
    @{ Id = "CoreyButler.NVMforWindows"; Name = "NVM for Windows" }
    @{ Id = "Google.AntigravityCLI"; Name = "Antigravity CLI"; Force = $true }

    # CLI base tools
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

    # Web Stack
    @{ Id = "PHP.PHP.8.4"; Name = "PHP" }
    @{ Id = "Composer.Composer"; Name = "Composer" }
    @{ Id = "Oracle.MySQL"; Name = "MySQL Server" }
)

$desktopPackages = @(
    @{ Id = "Brave.Brave"; Name = "Brave Browser" }
    @{ Id = "Google.Chrome"; Name = "Google Chrome" }
    @{ Id = "Obsidian.Obsidian"; Name = "Obsidian" }
    @{ Id = "OBSProject.OBSStudio"; Name = "OBS Studio" }
    @{ Id = "ElementLabs.LMStudio"; Name = "LM Studio" }
    @{ Id = "RARLab.WinRAR"; Name = "WinRAR"; Force = $true }
    @{ Id = "Jellyfin.Server"; Name = "Jellyfin Server" }
    @{ Id = "Discord.Discord"; Name = "Discord" }
    @{ Id = "qBittorrent.qBittorrent"; Name = "qBittorrent" }
    @{ Id = "Stremio.Stremio"; Name = "Stremio" }
    @{ Id = "HeroicGamesLauncher.HeroicGamesLauncher"; Name = "Heroic Games Launcher" }
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
)

$toInstall = @()
if ($Mode -eq 'full') {
    $toInstall += $basicPackages
    $toInstall += $desktopPackages
    $toInstall += $gamingPackages
} elseif ($Mode -eq 'basic') {
    $toInstall += $basicPackages
} elseif ($Mode -eq 'games') {
    $toInstall += $gamingPackages
}

if ($DryRun) {
    Write-Log "Running in DRY-RUN mode. The following apps would be installed:" -Level "INFO"
    foreach ($pkg in $toInstall) {
        Write-Log -Message "  $($pkg.Name) ($($pkg.Id))" -Level "INFO"
    }
    Write-Log -Message "Dry-run completed successfully." -Level "OK"
    exit 0
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
$successCodes = @(0, -1978335189, 2316697643, -1978335204, 2316697628, -1978335203, 2316697629, -1978335186, 2316697646)

foreach ($pkg in $toInstall) {
    Write-Log -Message "Installing $($pkg.Name) ($($pkg.Id))..." -Level "INFO"
    
    if ($pkg.Id -eq "Composer.Composer") {
        # Refresh environment variables first to make sure PHP is in PATH
        Update-ProcessEnvironment
        
        try {
            Write-Log -Message "Downloading Composer installer..." -Level "INFO"
            $tempPath = Join-Path $env:TEMP "Composer-Setup.exe"
            Invoke-WebRequest -Uri "https://getcomposer.org/Composer-Setup.exe" -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
            
            Write-Log -Message "Running Composer installer..." -Level "INFO"
            $process = Start-Process -FilePath $tempPath -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES" -Wait -PassThru -NoNewWindow
            $exitCode = $process.ExitCode
        } catch {
            Write-Log -Message "Failed to download or run Composer installer: $_" -Level "WARN"
            $exitCode = 1
        }
    } elseif ($pkg.Id -eq "RARLab.WinRAR") {
        try {
            Write-Log -Message "Downloading WinRAR installer..." -Level "INFO"
            $tempPath = Join-Path $env:TEMP "winrar-setup.exe"
            Invoke-WebRequest -Uri "https://www.rarlab.com/rar/winrar-x64-701.exe" -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
            
            Write-Log -Message "Running WinRAR installer..." -Level "INFO"
            # WinRAR requires elevation to install to Program Files, so we run with -Verb RunAs
            $process = Start-Process -FilePath $tempPath -ArgumentList "/S" -Verb RunAs -Wait -PassThru
            $exitCode = $process.ExitCode
        } catch {
            Write-Log -Message "Failed to download or run WinRAR installer: $_" -Level "WARN"
            $exitCode = 1
        }
    } else {
        $argsList = @("install", "-e", "--id", $pkg.Id, "--accept-package-agreements", "--accept-source-agreements")
        if ($pkg.Force) {
            $argsList += "--force"
        }
        & winget $argsList
        $exitCode = $LASTEXITCODE
    }

    if ($successCodes -contains $exitCode) {
        Write-Log -Message "$($pkg.Name) installed/updated successfully (or already installed)." -Level "OK"
    } else {
        Write-Log -Message "Failed to install $($pkg.Name) (Exit Code: $exitCode)." -Level "WARN"
        $failed += $pkg.Name
    }
}

Write-Section "Configuring PowerShell Profile"
$profileDir = Split-Path -Path $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

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
function a { php artisan @args }

# Podman to Docker compatibility aliases
function docker { podman @args }
function docker-compose { podman compose @args }
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

Write-Section "Installation Summary"
if ($failed.Count -eq 0) {
    Write-Log -Message "All requested applications installed successfully!" -Level "OK"
} else {
    Write-Log -Message "Installation finished with warnings. The following apps failed to install:`n  $($failed -join ', ')" -Level "WARN"
}
