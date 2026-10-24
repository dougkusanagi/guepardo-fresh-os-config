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
    [ValidateSet('full', 'basic', 'games', 'server', 'desktop', 'wsl')]
    [string]$Mode = 'full',

    [string]$Profiles,

    [switch]$Plan,

    [switch]$ListProfiles,

    [switch]$DryRun,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($ListProfiles) {
    Write-Host "cli, dev, web, desktop, games"
    exit 0
}

if ($Help) {
    Write-Host @"
Usage:
  .\install.ps1 [-Profiles cli,dev,web,desktop,games] [-Plan] [-DryRun]
  .\install.ps1 [-Mode <full|basic|games|server|desktop|wsl>]

Options:
  -Profiles Select independent profiles separated by commas.
  -Mode      Legacy shortcut; full, basic, games, server, desktop, or wsl.
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
    $title = "Select Installation Mode"
    $message = "Choose the scope of the installation:"
    $full = New-Object System.Management.Automation.Host.ChoiceDescription "&Full", "Dev tools + Desktop apps + Games"
    $basic = New-Object System.Management.Automation.Host.ChoiceDescription "&Basic", "Dev tools only"
    $games = New-Object System.Management.Automation.Host.ChoiceDescription "&Games", "Gaming apps only"
    $server = New-Object System.Management.Automation.Host.ChoiceDescription '&Server', 'CLI tools only'
    $desktopOnly = New-Object System.Management.Automation.Host.ChoiceDescription '&Desktop', 'Desktop apps only'
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($full, $basic, $games, $server, $desktopOnly)
    $decision = $Host.UI.PromptForChoice($title, $message, $choices, 0)
    
    switch ($decision) {
        0 { $Mode = 'full' }
        1 { $Mode = 'basic' }
        2 { $Mode = 'games' }
        3 { $Mode = 'server' }
        4 { $Mode = 'desktop' }
    }
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
    @{ Id = "guepardo.vite-plus"; Name = "Vite+ global CLI (vp)" }
    @{ Id = "OpenAI.Codex"; Name = "Codex CLI" }
    @{ Id = "Anthropic.ClaudeCode"; Name = "Claude Code CLI" }
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
    @{ Id = "Microsoft.OneDrive"; Name = "OneDrive Sync GUI (autostart)" }
    @{ Id = "guepardo.zapfast"; Name = "ZapFast" }
    @{ Id = "OpenAI.ChatGPT"; Name = "ChatGPT" }
    @{ Id = "Anthropic.Claude"; Name = "Claude Desktop" }
    @{ Id = "T3Tools.T3Code"; Name = "T3 Code" }
    @{ Id = "guepardo.sloth-note"; Name = "Sloth Note" }
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
    @{ Id = "Jellyfin.Server"; Name = "Jellyfin Server" }
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

if ($Profiles -and $PSBoundParameters.ContainsKey('Mode')) {
    throw "Use -Profiles or -Mode, not both."
}
if (-not $Profiles) {
    $Profiles = switch ($Mode) {
        'full'    { 'cli,dev,web,desktop,games' }
        'basic'   { 'cli,dev,web' }
        'server'  { 'cli' }
        'wsl'     { 'cli,dev,web' }
        'desktop' { 'desktop' }
        'games'   { 'games' }
    }
}
$selectedProfiles = @($Profiles.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$validProfiles = @('cli', 'dev', 'web', 'desktop', 'games')
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

if ('dev' -in $selectedProfiles -or 'desktop' -in $selectedProfiles) {
    $toInstall += @{ Id = 'guepardo.dotagents'; Name = 'dotagents (install + sync)' }
}

if ('desktop' -in $selectedProfiles) {
    Write-Log 'AI Quota Pulse is a GNOME extension and is unavailable on native Windows.' -Level WARN
}

if ($Plan -or $DryRun) {
    Write-Log "Installation plan for profiles: $($selectedProfiles -join ', ')" -Level "INFO"
    foreach ($pkg in $toInstall) {
        Write-Log -Message "  $($pkg.Name) ($($pkg.Id))" -Level "INFO"
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

function Install-RequiredWingetPackage {
    param ([string]$Id, [string[]]$ExtraArgs = @())
    & winget install -e --id $Id --source winget --silent --disable-interactivity --no-upgrade --accept-package-agreements --accept-source-agreements @ExtraArgs | Out-Host
    if ((Get-InstallResult $LASTEXITCODE) -eq 'failed') { throw "Dependency failed: $Id ($LASTEXITCODE)" }
    Update-ProcessEnvironment
}

function Get-GuepardoCheckout {
    param ([string]$Repo, [string]$Name)
    Install-RequiredWingetPackage 'Git.Git'
    $destination = Join-Path $env:LOCALAPPDATA "Guepardo/Sources/$Name"
    if (Test-Path (Join-Path $destination '.git')) {
        $origin = & git -C $destination remote get-url origin
        if ($LASTEXITCODE -ne 0 -or $origin -ne "https://github.com/$Repo.git") { throw "Unexpected repository: $destination" }
        & git -C $destination pull --ff-only | Out-Host
    } elseif (Test-Path $destination) { throw "Preserving existing directory: $destination" }
    else { & git clone --depth=1 "https://github.com/$Repo.git" $destination | Out-Host }
    if ($LASTEXITCODE -ne 0) { throw "Checkout failed: $Repo" }
    return $destination
}

function Install-Dotagents {
    $destination = Get-GuepardoCheckout 'dougkusanagi/dotagents' 'dotagents'
    # Upstream uses flock and real symlinks; use MSYS2's util-linux runtime.
    Install-RequiredWingetPackage 'MSYS2.MSYS2'
    $bash = Join-Path $env:SystemDrive 'msys64/usr/bin/bash.exe'
    if (-not (Test-Path $bash)) { throw 'MSYS2 Bash not found at the default installation path.' }
    New-Item -ItemType Directory (Join-Path $env:USERPROFILE '.codex') -Force | Out-Null
    New-Item -ItemType Directory (Join-Path $env:USERPROFILE '.claude') -Force | Out-Null
    $previousMsys = $env:MSYS
    try {
        $env:MSYS = 'winsymlinks:nativestrict'
        & $bash -c 'export PATH="/usr/bin:/bin:$PATH"; pacman -Syu --noconfirm'
        # Relaunch after the runtime upgrade before installing dependencies.
        if ($LASTEXITCODE -ne 0) { throw 'MSYS2 runtime upgrade failed; rerun the installer.' }
        & $bash -c 'export PATH="/usr/bin:/bin:$PATH"; pacman -Syu --noconfirm && pacman -S --noconfirm --needed util-linux git'
        if ($LASTEXITCODE -ne 0) { throw 'MSYS2 dotagents dependencies failed.' }
        & $bash -c 'export PATH="/usr/bin:/bin:$PATH"; export HOME="$(cygpath -u "$2")"; cd "$(cygpath -u "$1")" && bash ./install.sh && bash ./bin/sync' -- $destination $env:USERPROFILE
        if ($LASTEXITCODE -ne 0) { throw 'dotagents failed. Enable Windows Developer Mode or run elevated to allow symlinks.' }
    } finally { $env:MSYS = $previousMsys }
}

function Install-SlothNote {
    if (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs/Sloth Note/sloth-note.exe')) { return }
    $release = $null
    try { $release = Invoke-RestMethod 'https://api.github.com/repos/dougkusanagi/sloth-noter/releases/latest' -TimeoutSec 60 }
    catch {
        if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
    }
    $asset = $release.assets | Where-Object { $_.name -match 'x64.*setup\.exe$|x64.*-setup\.exe$' } | Select-Object -First 1
    if ($asset) {
        $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.exe')
        try {
            Invoke-WebRequest $asset.browser_download_url -OutFile $temp -TimeoutSec 600
            $process = Start-Process $temp -ArgumentList '/S' -Wait -PassThru
            if ((Get-InstallResult $process.ExitCode) -eq 'failed') { throw "Sloth Note installer failed: $($process.ExitCode)" }
        } finally { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
        return
    }
    Write-Log 'No public Sloth Note installer; building source with Bun/Rust/MSVC (may take several minutes).' -Level WARN
    Install-RequiredWingetPackage 'Oven-sh.Bun'
    Install-RequiredWingetPackage 'OpenJS.NodeJS.LTS'
    Install-RequiredWingetPackage 'Rustlang.Rustup'
    Install-RequiredWingetPackage 'Microsoft.VisualStudio.2022.BuildTools' @('--override', '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended')
    $destination = Get-GuepardoCheckout 'dougkusanagi/sloth-noter' 'sloth-noter'
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vsPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) { throw 'MSVC C++ build tools unavailable; restart Windows and rerun.' }
    $devCmd = Join-Path $vsPath 'Common7/Tools/VsDevCmd.bat'
    $devEnvironment = & cmd.exe /s /c "`"`"$devCmd`" -arch=x64 >nul && set`""
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize MSVC environment.' }
    foreach ($line in $devEnvironment) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process') }
    }
    $env:Path = (Join-Path $env:USERPROFILE '.cargo/bin') + ';' + $env:Path
    & rustup default stable
    if ($LASTEXITCODE -ne 0) { throw 'Rust toolchain setup failed.' }
    Push-Location $destination
    try {
        & bun install --frozen-lockfile
        if ($LASTEXITCODE -ne 0) { throw 'Sloth Note dependency installation failed.' }
        & bun run desktop:build --no-bundle
        if ($LASTEXITCODE -ne 0) { throw 'Sloth Note compilation failed.' }
        $appDir = Join-Path $env:LOCALAPPDATA 'Programs/Sloth Note'
        New-Item -ItemType Directory $appDir -Force | Out-Null
        Copy-Item 'src-tauri/target/release/sloth-note.exe' $appDir -Force
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Sloth Note.lnk'))
        $shortcut.TargetPath = Join-Path $appDir 'sloth-note.exe'
        $shortcut.Save()
    } finally { Pop-Location }
}

function Install-VitePlus {
    if (Get-Command vp -ErrorAction SilentlyContinue) { return }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.ps1')
    $savedHome = $env:VP_HOME; $savedNode = $env:VP_NODE_MANAGER; $savedPm = $env:VP_PM_MANAGER
    try {
        $env:VP_HOME = Join-Path $env:USERPROFILE '.vite-plus'
        $env:VP_NODE_MANAGER = 'no'; $env:VP_PM_MANAGER = 'no'
        Invoke-WebRequest 'https://vite.plus/ps1' -OutFile $temporary -TimeoutSec 300
        $powershellExe = (Get-Process -Id $PID).Path
        & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $temporary
        if ($LASTEXITCODE -ne 0) { throw "Vite+ global installer failed: $LASTEXITCODE" }
        Update-ProcessEnvironment
        $bin = Join-Path $env:USERPROFILE '.vite-plus/bin'
        $env:Path = "$bin;$env:Path"
        if (-not (Get-Command vp -ErrorAction SilentlyContinue)) { throw 'vp unavailable after Vite+ installation.' }
        & vp --version
        if ($LASTEXITCODE -ne 0) { throw 'vp verification failed.' }
    } finally {
        $env:VP_HOME = $savedHome; $env:VP_NODE_MANAGER = $savedNode; $env:VP_PM_MANAGER = $savedPm
        Remove-Item $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Enable-OneDriveAutostart {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft/OneDrive/OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive/OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive/OneDrive.exe')
    )
    $executable = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $executable) { throw 'OneDrive.exe unavailable after installation.' }
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name 'OneDrive' -Value ('"' + $executable + '" /background') -PropertyType String -Force | Out-Null
    Write-Log 'OneDrive GUI enabled at sign-in. Open OneDrive to authenticate and choose folders.'
}

function Install-ZapFast {
    if (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs/ZapFast/ZapFast.exe')) { return }
    $release = Invoke-RestMethod 'https://api.github.com/repos/crmne/zapfast/releases/latest' -TimeoutSec 60
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
    $asset = $release.assets | Where-Object { $_.name -match "-$architecture-pc-windows-msvc\.msi$" } | Select-Object -First 1
    $sums = $release.assets | Where-Object { $_.name -eq 'checksums.txt' } | Select-Object -First 1
    if (-not $asset -or -not $sums) { throw 'Compatible ZapFast installer/checksums unavailable.' }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory $temporary | Out-Null
    try {
        $msi = Join-Path $temporary 'ZapFast.msi'
        $checksums = Join-Path $temporary 'checksums.txt'
        Invoke-WebRequest $asset.browser_download_url -OutFile $msi -TimeoutSec 600
        Invoke-WebRequest $sums.browser_download_url -OutFile $checksums -TimeoutSec 60
        $expected = $null
        foreach ($line in Get-Content $checksums) {
            if ($line -match '^([a-fA-F0-9]{64})\s+\*?(.+)$' -and $Matches[2] -eq $asset.name) { $expected = $Matches[1]; break }
        }
        if (-not $expected -or (Get-FileHash $msi -Algorithm SHA256).Hash -ne $expected) { throw 'ZapFast SHA256 verification failed.' }
        $process = Start-Process msiexec.exe -ArgumentList @('/i', ('"' + $msi + '"'), '/qn', '/norestart') -Wait -PassThru
        $result = Get-InstallResult $process.ExitCode
        if ($result -eq 'failed') { throw "ZapFast installation failed: $($process.ExitCode)" }
        if ($result -eq 'reboot-required') { $script:rebootRequired = $true }
    } finally { Remove-Item $temporary -Recurse -Force -ErrorAction SilentlyContinue }
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

foreach ($pkg in $toInstall) {
    $packageIndex++
    Write-Log -Message "[$packageIndex/$($toInstall.Count)] Installing $($pkg.Name) ($($pkg.Id))..." -Level "INFO"
    
    $exitCode = 1
    if ($pkg.Id -in @('guepardo.dotagents', 'guepardo.sloth-note', 'guepardo.zapfast', 'guepardo.vite-plus')) {
        try {
            switch ($pkg.Id) {
                'guepardo.dotagents' { Install-Dotagents }
                'guepardo.sloth-note' { Install-SlothNote }
                'guepardo.zapfast' { Install-ZapFast }
                'guepardo.vite-plus' { Install-VitePlus }
            }
            $exitCode = 0
        } catch { Write-Log "Failed to install $($pkg.Name): $_" -Level WARN; $exitCode = 1 }
    } elseif ($pkg.Id -eq "Composer.Composer") {
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
            if ($pkg.Id -eq 'Microsoft.OneDrive' -and (Get-InstallResult $exitCode) -ne 'failed') { Enable-OneDriveAutostart }
        } catch {
            Write-Log -Message "Failed to run winget for $($pkg.Name): $_" -Level 'WARN'
            $exitCode = 1
        }
    }

    $result = Get-InstallResult $exitCode
    if ($result -eq 'reboot-required') { $rebootRequired = $true }
    if ($result -ne 'failed') {
        Write-Log -Message "$($pkg.Name) installed/updated successfully (or already installed)." -Level "OK"
    } else {
        Write-Log -Message "Failed to install $($pkg.Name) (Exit Code: $exitCode)." -Level "WARN"
        $failed += $pkg.Name
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
