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

    [switch]$Help,
    [string[]]$Apps,
    [string[]]$ExcludeApps,
    [ValidateSet('auto','winget','scoop')][string]$Provider = 'auto',
    [switch]$BootstrapScoop,
    [switch]$Resume,
    [switch]$RetryFailed,
    [switch]$InteractiveFallback,
    [switch]$Doctor,
    [switch]$NoColor,
    [switch]$NoPrefetch,
    [switch]$PrefetchOnly,
    [ValidateRange(1,8)][int]$Jobs = 4,
    [string]$StateDirectory,
    [string]$CacheDirectory
)

$ErrorActionPreference = 'Stop'
# A standalone entry point must fetch the modules and catalog as one source tree.
if (-not $PSScriptRoot -or -not (Test-Path (Join-Path $PSScriptRoot 'catalog/apps.json'))) {
    $sourceRef = if ($env:GUEPARDO_REF) { $env:GUEPARDO_REF } else { 'master' }
    if ($sourceRef -notmatch '^[A-Za-z0-9._/-]+$') { throw 'Invalid GUEPARDO_REF.' }
    $bootstrapDirectory = Join-Path ([IO.Path]::GetTempPath()) ('guepardo-source-'+[guid]::NewGuid())
    New-Item -ItemType Directory $bootstrapDirectory | Out-Null
    try {
        $archive = Join-Path $bootstrapDirectory 'source.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/dougkusanagi/guepardo-fresh-os-config/zip/$sourceRef" -OutFile $archive -TimeoutSec 300
        Expand-Archive -LiteralPath $archive -DestinationPath $bootstrapDirectory
        $checkout = Get-ChildItem -LiteralPath $bootstrapDirectory -Directory | Select-Object -First 1
        & (Join-Path $checkout.FullName 'install.ps1') @PSBoundParameters
        exit $LASTEXITCODE
    } finally { Remove-Item -LiteralPath $bootstrapDirectory -Recurse -Force }
}
if ($env:NO_COLOR) { $NoColor = $true }
$moduleRoot = Join-Path $PSScriptRoot 'modules/installer'
foreach ($moduleName in @('catalog','state','download','providers','ui','releases')) {
    . (Join-Path $moduleRoot "$moduleName.ps1")
}
$catalog = Get-GuepardoCatalog
# powershell.exe -File (used by install.cmd) passes comma lists as one string.
$Apps = @($Apps | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$ExcludeApps = @($ExcludeApps | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Doctor) {
    Write-GuepardoHeading 'guepardo / diagnóstico' -NoColor:$NoColor
    foreach ($tool in @('winget','scoop','curl.exe','git','node','cargo')) {
        $found = Get-Command $tool -ErrorAction SilentlyContinue
        Write-Host ("  {0,-12} {1}" -f $tool, $(if ($found) { $found.Source } else { 'não encontrado' }))
    }
    Write-Host "  Catálogo: $($catalog.apps.Count) aplicativos; arquitetura: $env:PROCESSOR_ARCHITECTURE"
    Write-Host '  Downloads lentos no Winget: compare network.downloader=wininet com Delivery Optimization em winget settings.'
    Write-Host '  Nenhuma instalação ou alteração de configuração foi feita.'
    exit 0
}


if ($ListProfiles) {
    Write-Host ((@($catalog.profiles | Where-Object { 'windows' -in $_.platforms } | ForEach-Object { $_.id })) -join ', ')
    exit 0
}

if ($Help) {
    Write-Host @"
Usage:
  .\install.ps1 [-Profiles cli,dev,web,desktop,games,jellyfin,wsl2] [-Plan] [-DryRun]
  .\install.ps1 [-Mode <full|basic|games|server|desktop|wsl>]

Options:
  -Profiles Select independent profiles separated by commas.
  -Mode      Legacy shortcut; full, basic, games, server, desktop, or wsl.
  -Plan      Show the package plan without changes.
  -ListProfiles List available profiles.
  -DryRun    Show what would be installed without making any changes.
  -Apps / -ExcludeApps Select individual catalog IDs (dependencies are included).
  -Provider auto|winget|scoop  Auto prefers Scoop for supported tools when available.
  -BootstrapScoop Install Scoop and aria2 from a non-elevated terminal.
  -Resume / -RetryFailed Resume verified results / rerun only pending or failed steps.
  -Jobs 1..8 Download concurrency (installations remain serial).
  -StateDirectory / -CacheDirectory Override persistent state/cache locations.
  -InteractiveFallback Allow a visible Winget installer after a silent failure.
  -NoPrefetch / -PrefetchOnly Disable prefetch / only prepare direct downloads.
  -Doctor / -NoColor Diagnostic mode / plain console output.
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
if (-not $StateDirectory) { $StateDirectory = Join-Path $statePath 'Guepardo/State' }
if (-not $CacheDirectory) { $CacheDirectory = Join-Path $statePath 'Guepardo/Cache' }
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

    if ($NoColor) { Write-Host "[$Level] $Message"; return }
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
    Write-GuepardoHeading $Title -NoColor:$NoColor
    Write-Log -Message "=== Section: $Title ===" -Level "INFO"
}

# Ascii Art
function Show-Intro {
    Write-GuepardoHeading 'guepardo / Windows' -NoColor:$NoColor
    Write-Host '  Fresh Config Installer (Windows)'
    Write-Host "  $($toInstall.Count) aplicativos | Provedor: $Provider | Downloads: $Jobs"
    Write-Host "  Log: $logFile`n"
}

# Interactive profile/app selection uses the same catalog as noninteractive plans.
$modeExplicitlySet = $PSBoundParameters.ContainsKey('Mode') -or $PSBoundParameters.ContainsKey('Profiles') -or $Apps.Count -gt 0
if ($Resume -and -not $modeExplicitlySet -and -not $RetryFailed) {
    $resumeState = Read-GuepardoState (Join-Path $StateDirectory 'install-state.json')
    $Apps = @($resumeState.selection)
    if ($Apps.Count -eq 0) { $Apps = @($resumeState.packages.Keys) }
    if ($Apps.Count -eq 0) { throw 'No previous installation to resume. Select profiles or apps first.' }
    $modeExplicitlySet = $true
}
if (-not $modeExplicitlySet -and -not $Plan -and -not $DryRun -and -not $RetryFailed -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    $Apps = @(Select-GuepardoApps -Catalog $catalog -NoColor:$NoColor)
}
if ($Profiles -and $PSBoundParameters.ContainsKey('Mode')) {
    throw "Use -Profiles or -Mode, not both."
}
if (-not $Profiles) {
    $Profiles = switch ($Mode) {
        'full'    { 'cli,dev,web,desktop,games' }
        'basic'   { 'cli,dev,web' }
        'server'  { 'cli' }
        'wsl'     { 'cli,dev,web,wsl2' }
        'jellyfin' { 'jellyfin' }
        'desktop' { 'desktop' }
        'games'   { 'games' }
    }
}
$selectedProfiles = @($Profiles.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$validProfiles = @($catalog.profiles | Where-Object { 'windows' -in $_.platforms } | ForEach-Object { $_.id })
foreach ($profileName in $selectedProfiles) {
    if ($profileName -notin $validProfiles) { throw "Unknown profile: $profileName" }
}
if ($selectedProfiles.Count -eq 0) { throw 'Select at least one profile.' }

$toInstall = @(Resolve-GuepardoPlan -Catalog $catalog -Profiles $selectedProfiles -Apps $Apps -ExcludeApps $ExcludeApps)
if ($toInstall.Count -eq 0) { throw 'Select at least one app.' }
if ($PrefetchOnly -and $NoPrefetch) { throw 'Use -PrefetchOnly or -NoPrefetch, not both.' }
if ($Apps.Count -gt 0) {
    $selectedProfiles = @($catalog.apps | Where-Object { $_.id -in @($toInstall | ForEach-Object { $_.Id }) } | ForEach-Object { $_.profiles } | Select-Object -Unique)
}

Show-Intro
if ('desktop' -in $selectedProfiles) {
    Write-Log 'AI Quota Pulse is a GNOME extension and is unavailable on native Windows.' -Level WARN
}

if ($RetryFailed -and ($Plan -or $DryRun)) {
    $previewState = Read-GuepardoState (Join-Path $StateDirectory 'install-state.json')
    $pendingIds = @(Get-GuepardoPendingIds $previewState)
    if ($pendingIds.Count -eq 0) { Write-Host 'Nenhuma pendência na execução anterior.'; exit 0 }
    $toInstall = @(Resolve-GuepardoPlan -Catalog $catalog -Profiles @() -Apps $pendingIds -ExcludeApps $ExcludeApps)
}
if ($Plan -or $DryRun) {
    Write-Log "Installation plan for profiles: $($selectedProfiles -join ', ')" -Level "INFO"
    foreach ($pkg in $toInstall) {
        Write-Log -Message "  $($pkg.Name) ($($pkg.Id))" -Level "INFO"
    }
    Write-Log -Message "Dry-run completed successfully." -Level "OK"
    exit 0
}

if (-not $PrefetchOnly -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
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

function Install-NodeLts {
    Update-ProcessEnvironment
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($node -and (Get-Command npm.cmd -ErrorAction SilentlyContinue) -and ((& $node.Source --version) -match '^v(22|24)\.')) { return }
    $nvm = (Get-Command nvm.exe -ErrorAction SilentlyContinue).Source
    if (-not $nvm) {
        $nvmHome = @($env:NVM_HOME, [Environment]::GetEnvironmentVariable('NVM_HOME', 'User'), [Environment]::GetEnvironmentVariable('NVM_HOME', 'Machine')) | Where-Object { $_ } | Select-Object -First 1
        if ($nvmHome -and (Test-Path (Join-Path $nvmHome 'nvm.exe'))) { $nvm = Join-Path $nvmHome 'nvm.exe' }
    }
    if (-not $nvm) { throw 'NVM for Windows not found after installation; restart the terminal and rerun.' }
    & $nvm install lts
    if ($LASTEXITCODE -ne 0) { throw "nvm install lts failed: $LASTEXITCODE" }
    & $nvm use lts
    if ($LASTEXITCODE -ne 0) { throw "nvm use lts failed: $LASTEXITCODE" }
    Update-ProcessEnvironment
    if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -or -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
        throw 'NVM finished without exposing node.exe and npm.cmd in PATH.'
    }
}

function Install-Wsl {
    # Returns an installer exit code: 0 configured, 3010 restart required.
    $wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
    if (-not (Test-Path -LiteralPath $wsl)) { throw 'wsl.exe not found. Use Windows 10 build 19041 or Windows 11.' }
    $adminScript = @'
$ErrorActionPreference = 'Stop'
$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
$restartNeeded = $false
foreach ($featureName in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    if ((Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart).RestartNeeded) { $restartNeeded = $true }
}
if ($restartNeeded) { exit 3010 }
$distros = @(& $wsl --list --quiet 2>$null | ForEach-Object { ([string]$_).Replace([string][char]0, '').Trim() } | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) { $distros = @() }
if ($distros -notcontains 'Ubuntu') {
    & $wsl --install --distribution Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
& $wsl --update
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $wsl --set-default-version 2
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $wsl --set-version Ubuntu 2
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $wsl --set-default Ubuntu
exit $LASTEXITCODE
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($adminScript))
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $powershellExe = (Get-Process -Id $PID).Path
    $process = if ($isAdmin) { Start-Process $powershellExe -ArgumentList $arguments -Wait -PassThru }
               else { Start-Process $powershellExe -ArgumentList $arguments -Verb RunAs -Wait -PassThru }
    if ($process.ExitCode -eq 0) { Write-Log 'WSL 2 and Ubuntu configured. Open `wsl -d Ubuntu` to create your Linux user.' -Level OK }
    return $process.ExitCode
}

function Install-JellyfinConfiguration {
    $module = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'modules/jellyfin.ps1' } else { $null }
    if (-not $module -or -not (Test-Path -LiteralPath $module)) {
        throw 'modules/jellyfin.ps1 not found; run install.ps1 from a repository checkout.'
    }
    $powershellExe = (Get-Process -Id $PID).Path
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File $module -SkipInstall
    if ($LASTEXITCODE -ne 0) { throw "Jellyfin configuration failed: $LASTEXITCODE" }
}

function Install-SlothNote {
    if (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs/Sloth Note/sloth-note.exe')) { return }
    $release = $null
    try { $release = Get-GuepardoRelease 'dougkusanagi/sloth-noter' }
    catch {
        if ([int]$_.Exception.Response.StatusCode -ne 404) { throw }
    }
    $asset = $release.assets | Where-Object { $_.name -match 'x64.*setup\.exe$|x64.*-setup\.exe$' } | Select-Object -First 1
    if ($asset) {
        $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.exe')
        try {
            Receive-GuepardoFile -Uri $asset.browser_download_url -Destination $temp -Sha256 (Get-GuepardoAssetChecksum $asset) -CacheDirectory $CacheDirectory
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
        Receive-GuepardoFile -Uri 'https://vite.plus/ps1' -Destination $temporary -CacheDirectory $CacheDirectory -MaxAgeSeconds 0
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
    $release = Get-GuepardoRelease 'crmne/zapfast'
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
    $asset = $release.assets | Where-Object { $_.name -match "-$architecture-pc-windows-msvc\.msi$" } | Select-Object -First 1
    $sums = $release.assets | Where-Object { $_.name -eq 'checksums.txt' } | Select-Object -First 1
    if (-not $asset -or -not $sums) { throw 'Compatible ZapFast installer/checksums unavailable.' }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory $temporary | Out-Null
    try {
        $msi = Join-Path $temporary 'ZapFast.msi'
        $checksums = Join-Path $temporary 'checksums.txt'
        Receive-GuepardoFile -Uri $sums.browser_download_url -Destination $checksums -CacheDirectory $CacheDirectory -MaxAgeSeconds 0
        $expected = Get-GuepardoChecksumFromFile -Path $checksums -Name $asset.name
        Receive-GuepardoFile -Uri $asset.browser_download_url -Destination $msi -Sha256 $expected -CacheDirectory $CacheDirectory
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
$runLock = Enter-GuepardoLock $StateDirectory
try {
$stateFile = Join-Path $StateDirectory 'install-state.json'
$installState = Read-GuepardoState $stateFile
if ($RetryFailed) {
    if ($installState.packages.Count -eq 0) { throw 'No previous run to retry.' }
    $retryIds = @(Get-GuepardoPendingIds $installState)
    if ($retryIds.Count -eq 0) { Write-Host 'Nenhuma pendência na execução anterior.'; exit 0 }
    $toInstall = @(Resolve-GuepardoPlan -Catalog $catalog -Profiles @() -Apps $retryIds -ExcludeApps $ExcludeApps)
    $selectedProfiles = @($toInstall | ForEach-Object { $_.Definition.profiles } | Select-Object -Unique)
}
if (-not $PrefetchOnly) {
    $installState.selection = @($toInstall | ForEach-Object { $_.Id })
    foreach($pendingPackage in $toInstall) {
        if(-not $installState.packages.ContainsKey($pendingPackage.Id)) {
            $installState.packages[$pendingPackage.Id]=@{status='pending';fingerprint=Get-GuepardoFingerprint $pendingPackage.Definition}
        }
    }
    Save-GuepardoState $installState $stateFile
}
if ($BootstrapScoop -and -not $PrefetchOnly) { Install-GuepardoScoop $CacheDirectory }
if (-not $PrefetchOnly) { foreach ($candidate in $toInstall) { $null = Get-GuepardoProvider $candidate $Provider } }
$prefetchRoot = Join-Path $StateDirectory 'prefetch'
if (-not $NoPrefetch) {
    $downloads = @(Get-GuepardoPrefetchPlan -Packages $toInstall -Directory $prefetchRoot -CacheDirectory $CacheDirectory)
    if ($downloads.Count -gt 0) {
        try { Invoke-GuepardoPrefetch -Downloads $downloads -CacheDirectory $CacheDirectory -Jobs $Jobs }
        catch {
            if ($PrefetchOnly) { throw }
            Write-Log "Some prefetch downloads failed; each app will retry individually: $_" -Level WARN
        }
    }
}
if ($PrefetchOnly) { Write-Host "Downloads preparados em $CacheDirectory"; exit 0 }
$results = @{}
foreach ($pkg in $toInstall) {
    $packageIndex++
    Write-Log -Message "[$packageIndex/$($toInstall.Count)] Installing $($pkg.Name) ($($pkg.Id))..." -Level "INFO"
    
    $packageProvider = Get-GuepardoProvider -Package $pkg -Preferred $Provider
    $blocked = @($pkg.DependsOn | Where-Object { $results[$_] -in @('failed','blocked','reboot-required') })
    if ($blocked.Count -gt 0) {
        $results[$pkg.Id] = 'blocked'; $failed += $pkg.Name
        Set-GuepardoPackageState $installState $stateFile $pkg 'blocked' $packageProvider ("Dependencies: " + ($blocked -join ', '))
        Write-GuepardoResult $pkg.Name 'bloqueado' ($blocked -join ', ') -NoColor:$NoColor
        continue
    }
    # Detect either provider before choosing one, avoiding duplicate installations.
    $detectedProvider = $packageProvider
    $installed = Test-GuepardoPackage $pkg $packageProvider
    if (-not $installed -and $packageProvider -eq 'scoop' -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        if (Test-GuepardoPackage $pkg 'winget' -RegistrationOnly) {
            $packageProvider='winget'; $detectedProvider='winget'; $installed=Test-GuepardoPackage $pkg 'winget'
        }
    }
    if (-not $installed -and $packageProvider -eq 'winget' -and $pkg.Definition.windows.scoop -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
        if (Test-GuepardoPackage $pkg 'scoop' -RegistrationOnly) {
            $packageProvider='scoop'; $detectedProvider='scoop'; $installed=Test-GuepardoPackage $pkg 'scoop'
        }
    }
    $previous = $installState.packages[$pkg.Id]
    $sameDefinition = $previous -and $previous.fingerprint -eq (Get-GuepardoFingerprint $pkg.Definition)
    if ($installed -and (-not $Resume -or ($sameDefinition -and $previous.status -in @('installed','already-installed')))) {
        $results[$pkg.Id] = 'already-installed'
        Set-GuepardoPackageState $installState $stateFile $pkg 'already-installed' $detectedProvider
        Write-GuepardoResult $pkg.Name 'já instalado' $detectedProvider -NoColor:$NoColor
        continue
    }
    Set-GuepardoPackageState $installState $stateFile $pkg 'running' $packageProvider
    $packageLog = Join-Path $logDir ("package-$timestamp-$pid-$($pkg.Id).log")
    Write-Progress -Activity 'Instalando aplicativos' -Status "$packageIndex/$($toInstall.Count) $($pkg.Name)" -PercentComplete ([int](100*($packageIndex-1)/[Math]::Max(1,$toInstall.Count)))
    $exitCode = 1
    if ($pkg.Id -in @('guepardo.dotagents', 'guepardo.sloth-note', 'guepardo.zapfast', 'guepardo.vite-plus', 'guepardo.node-lts', 'guepardo.jellyfin-config', 'guepardo.wsl2')) {
        try {
            $exitCode = 0
            switch ($pkg.Id) {
                'guepardo.dotagents' { Install-Dotagents }
                'guepardo.sloth-note' { Install-SlothNote }
                'guepardo.zapfast' { Install-ZapFast }
                'guepardo.vite-plus' { Install-VitePlus }
                'guepardo.node-lts' { Install-NodeLts }
                'guepardo.jellyfin-config' { Install-JellyfinConfiguration }
                'guepardo.wsl2' { $exitCode = [int](Install-Wsl | Select-Object -Last 1) }
            }
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
            Receive-GuepardoFile -Uri "https://getcomposer.org/Composer-Setup.exe" -Destination $tempPath -CacheDirectory $CacheDirectory -MaxAgeSeconds 900
            
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
        try {
            $exitCode = Invoke-GuepardoManagedInstall -Package $pkg -Provider $packageProvider -LogFile $packageLog -InteractiveFallback:$InteractiveFallback
            if ($pkg.Id -eq 'Microsoft.OneDrive' -and (Get-InstallResult $exitCode) -ne 'failed') { Enable-OneDriveAutostart }
        } catch {
            Write-Log -Message "Failed to run installer for $($pkg.Name): $_" -Level 'WARN'
            $exitCode = 1
        }
    }

    $result = Get-InstallResult $exitCode
    if ($result -eq 'reboot-required') { $rebootRequired = $true }
    if ($result -in @('installed','already-installed')) {
        Update-ProcessEnvironment
        $configurationOnly = $pkg.Id -in @('guepardo.dotagents','guepardo.jellyfin-config','guepardo.wsl2')
        if (-not $configurationOnly -and -not (Test-GuepardoPackage $pkg $packageProvider)) {
            $result = 'failed'
            Write-Log "Installer returned success but package verification failed: $($pkg.Id)" -Level WARN
        }
    }
    $results[$pkg.Id] = $result
    $diagnosticLog = if (Test-Path -LiteralPath $packageLog) { $packageLog } else { $logFile }
    Set-GuepardoPackageState $installState $stateFile $pkg $result $packageProvider "ExitCode=$exitCode; Log=$diagnosticLog"
    Write-GuepardoResult $pkg.Name $(if ($result -eq 'failed') { 'falhou' } elseif ($result -eq 'reboot-required') { 'reinício pendente' } else { 'concluído' }) $packageProvider -NoColor:$NoColor
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

Write-Progress -Activity "Instalando aplicativos" -Completed
Write-Section "Installation Summary"
$elapsed = (Get-Date) - $startedAt
Write-Log -Message "Completed $($toInstall.Count) packages in $([math]::Round($elapsed.TotalMinutes, 1)) min. Log: $logFile" -Level "INFO"
if ($failed.Count -eq 0) {
    Write-Log -Message "All requested applications installed successfully!" -Level "OK"
} else {
    Write-Log -Message "Installation finished with warnings. The following apps failed to install:`n  $($failed -join ', ')" -Level "WARN"
    Write-Log -Message 'Repita apenas as pendências: .\install.cmd -RetryFailed. Para retomar: -Resume. Diagnóstico: -Doctor.' -Level 'INFO'
}
if ($rebootRequired) { Write-Log -Message 'Restart Windows to finish installing the applications.' -Level 'WARN' }
if ($failed.Count -gt 0) { exit 1 }
exit 0
} finally {
    if ($runLock) { $runLock.Dispose() }
    Write-Progress -Activity 'Instalando aplicativos' -Completed
}
