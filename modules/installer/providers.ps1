function Get-GuepardoProvider {
    param($Package, [ValidateSet('auto','winget','scoop')][string]$Preferred = 'auto')
    if ($Package.Definition.windows.provider -eq 'custom') { return 'custom' }
    if ($Preferred -ne 'winget' -and $Package.Definition.windows.scoop -and (Get-Command scoop -ErrorAction SilentlyContinue)) { return 'scoop' }
    if ($Preferred -eq 'scoop' -and $Package.Definition.windows.scoop) { throw 'Scoop is not installed. Use -BootstrapScoop from a non-elevated terminal.' }
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
        $prefix = (& scoop prefix $Package.Definition.windows.scoop 2>$null | Out-String).Trim()
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
        $savedErrorPreference = $ErrorActionPreference
        $output = @()
        try {
        # Native stderr is an error record in PowerShell 5, even on successful exits.
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        if ($Provider -eq 'scoop') {
            $output = @(& scoop install $Package.Definition.windows.scoop 2>&1)
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

function Install-GuepardoScoop {
    param([string]$CacheDirectory)
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ((New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Install Scoop from a non-elevated terminal; elevation is handled by individual installers.'
    }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ("guepardo-scoop-$([guid]::NewGuid()).ps1")
    try {
        Receive-GuepardoFile -Uri 'https://get.scoop.sh' -Destination $temporary -CacheDirectory $CacheDirectory -MaxAgeSeconds 0
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temporary
        if ($LASTEXITCODE -ne 0) { throw 'Scoop bootstrap failed.' }
        $env:Path = (Join-Path $env:USERPROFILE 'scoop/shims') + ';' + $env:Path
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw 'Scoop is unavailable after bootstrap.' }
        & scoop install aria2
        if ($LASTEXITCODE -ne 0) { throw 'aria2 installation failed.' }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
