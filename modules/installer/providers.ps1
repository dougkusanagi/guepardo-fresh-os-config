function Get-GuepardoProvider {
    param($Package, [ValidateSet('auto','winget','scoop')][string]$Preferred = 'scoop')
    if ($Package.Definition.windows.provider -eq 'custom') { return 'custom' }
    if ($Preferred -ne 'winget' -and $Package.Definition.windows.scoop -and (Get-Command scoop -ErrorAction SilentlyContinue)) { return 'scoop' }
    if ($Preferred -ne 'winget' -and $Package.Definition.windows.scoop) { throw 'Scoop preparation did not finish. Retry the installer; use -Provider winget only to choose Winget explicitly.' }
    return 'winget'
}

function Test-GuepardoPackage {
    param($Package, [string]$Provider, [switch]$RegistrationOnly)
    if ($Provider -eq 'winget') {
        $savedErrorPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & winget list --id $Package.Id --exact --source winget --disable-interactivity --accept-source-agreements 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $savedErrorPreference }
        $registered = $code -eq 0 -and $output -match ('(?im)(?:^|\s)' + [regex]::Escape($Package.Id) + '(?:\s|$)')
        if (-not $registered -or $RegistrationOnly) { return $registered }
        foreach ($command in $Package.Definition.windows.commands) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { return $false } }
        return $true
    }
    if ($Provider -eq 'scoop') {
        try { $prefix = (& scoop prefix $Package.Definition.windows.scoop 2>$null | Out-String).Trim() }
        catch { return $false }
        $registered = $LASTEXITCODE -eq 0 -and $prefix -and (Test-Path -LiteralPath $prefix)
        if (-not $registered -or $RegistrationOnly) { return $registered }
        foreach ($command in $Package.Definition.windows.commands) { if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { return $false } }
        return $true
    }
    switch ($Package.Id) {
        'guepardo.sloth-note' { return Test-Path (Join-Path $env:LOCALAPPDATA 'Programs/Sloth Note/sloth-note.exe') }
        'guepardo.zapfast' { return Test-Path (Join-Path $env:LOCALAPPDATA 'Programs/ZapFast/ZapFast.exe') }
        'guepardo.vite-plus' { return [bool](Get-Command vp -ErrorAction SilentlyContinue) }
        'guepardo.node-lts' { return [bool](Get-Command node.exe -ErrorAction SilentlyContinue) -and [bool](Get-Command npm.cmd -ErrorAction SilentlyContinue) }
        'Composer.Composer' { return [bool](Get-Command composer -ErrorAction SilentlyContinue) }
        # Configuration steps must run again: installed binaries don't prove sync/theme/WSL state.
        default { return $false }
    }
}

function Invoke-GuepardoManagedInstall {
    param($Package, [string]$Provider, [string]$LogFile, [ValidateRange(1,5)][int]$Attempts = 3, [switch]$InteractiveFallback)
    $code = 1
    for ($attempt=1; $attempt -le $Attempts; $attempt++) {
        Add-Content -LiteralPath $LogFile -Value "[$([DateTime]::UtcNow.ToString('o'))] $($Package.Id) provider=$Provider attempt=$attempt"
        $savedErrorPreference = $ErrorActionPreference
        $output = @()
        try {
        # Native stderr is an error record in PowerShell 5, even on successful exits.
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        if ($Provider -eq 'scoop') {
            $scoopName = $Package.Definition.windows.scoop
            if ($Package.Definition.windows.scoopBucket) { $scoopName = "$($Package.Definition.windows.scoopBucket)/$scoopName" }
            $output = @(& scoop install $scoopName 2>&1)
        } else {
            $output = @(& winget install --id $Package.Id --exact --source winget --silent --disable-interactivity --no-upgrade --accept-package-agreements --accept-source-agreements --verbose-logs 2>&1)
        }
        $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $savedErrorPreference }
        $output | ForEach-Object { $_.ToString() } | Add-Content -LiteralPath $LogFile
        if ((Get-InstallResult $code) -ne 'failed') { return $code }
        # Only retry network/transport errors, never installer failures or cancelled UAC.
        $normalized = ([long]$code) -band 4294967295L
        if ($normalized -notin @(12002,12007,12029,12030,12031,2147954402,2147954407,2147954429,2147954430,2147954431)) { break }
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds ([Math]::Pow(2,$attempt-1)) }
    }
    $output | Select-Object -Last 5 | ForEach-Object { Write-Warning $_.ToString() }
    if ($InteractiveFallback -and $Provider -eq 'winget' -and $code -ne 0) {
        & winget install --id $Package.Id --exact --source winget --interactive --no-upgrade --accept-package-agreements --accept-source-agreements --verbose-logs 2>&1 | Tee-Object -FilePath $LogFile -Append | Out-Host
        return $LASTEXITCODE
    }
    return $code
}

function Test-GuepardoAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-GuepardoScoopRoot {
    if ($env:SCOOP) { return $env:SCOOP }
    $registered = [Environment]::GetEnvironmentVariable('SCOOP','User')
    if ($registered) { return $registered }
    $command = Get-Command scoop -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        $parent = Split-Path $command.Source -Parent
        if ($parent -and (Split-Path $parent -Leaf) -eq 'shims') { return Split-Path $parent -Parent }
    }
    return Join-Path $env:USERPROFILE 'scoop'
}

function Install-GuepardoScoop {
    param([string]$CacheDirectory, [string[]]$Buckets = @())
    # A terminal opened before Scoop was installed still has the old PATH.
    $knownRoot = Get-GuepardoScoopRoot
    $knownShims = Join-Path $knownRoot 'shims'
    if ((Test-Path -LiteralPath (Join-Path $knownShims 'scoop.ps1')) -or (Test-Path -LiteralPath (Join-Path $knownShims 'scoop.cmd'))) {
        $env:Path = $knownShims + ';' + $env:Path
    }
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ("guepardo-scoop-$([guid]::NewGuid()).ps1")
        try {
            Receive-GuepardoFile -Uri 'https://get.scoop.sh' -Destination $temporary -CacheDirectory $CacheDirectory -MaxAgeSeconds 0
            $bootstrapArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$temporary)
            if (Test-GuepardoAdministrator) { $bootstrapArgs += '-RunAsAdmin' }
            & powershell.exe @bootstrapArgs
            if ($LASTEXITCODE -ne 0) { throw 'Scoop bootstrap failed; app installation has not started. Retry the installer.' }
        } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    }
    $scoopRoot = Get-GuepardoScoopRoot
    $env:Path = (Join-Path $scoopRoot 'shims') + ';' + $env:Path
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw 'Scoop is unavailable after bootstrap.' }
    $managedAria2 = Join-Path $scoopRoot 'apps/aria2/current/aria2c.exe'
    if (-not (Test-Path -LiteralPath $managedAria2)) {
        & scoop install aria2
        if ($LASTEXITCODE -ne 0) { throw 'aria2 installation failed; retry the installer.' }
        if (-not (Test-Path -LiteralPath $managedAria2)) { throw 'Scoop reported success but aria2 was not installed.' }
    }
    foreach ($key in @('aria2-enabled','aria2-fallback-enabled')) {
        & scoop config $key true | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Scoop configuration failed: $key" }
    }
    & scoop config aria2-warning-enabled false | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Scoop aria2 configuration failed.' }
    foreach ($bucket in $Buckets) {
        if ($bucket -eq 'main') { continue }
        if ($bucket -ne 'extras') { throw "Unsupported Scoop bucket: $bucket" }
        if (-not (Test-Path -LiteralPath (Join-Path $scoopRoot "buckets/$bucket"))) {
            if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
                & scoop install git
                if ($LASTEXITCODE -ne 0) { throw 'Git is required to prepare Scoop extras.' }
            }
            & scoop bucket add extras https://github.com/ScoopInstaller/Extras
            if ($LASTEXITCODE -ne 0) { throw 'Scoop extras preparation failed.' }
        }
    }
}
