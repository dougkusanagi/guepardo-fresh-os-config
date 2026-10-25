$script:GuepardoReleases = @{}
function Get-GuepardoRelease {
    param([string]$Repository,[switch]$AllowMissing)
    if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid release repository.' }
    if (-not $script:GuepardoReleases.ContainsKey($Repository)) {
        try { $script:GuepardoReleases[$Repository] = Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/latest" -TimeoutSec 60 }
        catch {
            if ($AllowMissing -and $_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { $script:GuepardoReleases[$Repository]=$null }
            else { throw }
        }
    }
    return $script:GuepardoReleases[$Repository]
}

function Get-GuepardoAssetChecksum {
    param($Asset)
    if ($Asset.digest -match '^sha256:([a-fA-F0-9]{64})$') { return $Matches[1] }
    return ''
}

function Get-GuepardoChecksumFromFile {
    param([string]$Path, [string]$Name)
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([a-fA-F0-9]{64})\s+\*?(.+)$' -and $Matches[2] -eq $Name) { return $Matches[1] }
    }
    throw "Checksum not found for $Name"
}

function Get-GuepardoPrefetchPlan {
    param([object[]]$Packages, [string]$Directory, [string]$CacheDirectory)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    foreach ($pkg in $Packages) {
        try {
            switch ($pkg.Id) {
                'guepardo.sloth-note' {
                    $release = Get-GuepardoRelease 'dougkusanagi/sloth-noter' -AllowMissing
                    if (-not $release) { Write-Verbose 'Sloth Note has no published installer; its source-build step will run.' }
                    $asset = $release.assets | Where-Object { $_.name -match 'x64.*setup\.exe$|x64.*-setup\.exe$' } | Select-Object -First 1
                    if ($asset) { @{ Uri=$asset.browser_download_url; Sha256=Get-GuepardoAssetChecksum $asset; Destination=Join-Path $Directory 'sloth-note.exe' } }
                }
                'guepardo.zapfast' {
                    $release = Get-GuepardoRelease 'crmne/zapfast'
                    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
                    $asset = $release.assets | Where-Object { $_.name -match "-$architecture-pc-windows-msvc\.msi$" } | Select-Object -First 1
                    $sums = $release.assets | Where-Object { $_.name -eq 'checksums.txt' } | Select-Object -First 1
                    if ($asset -and $sums) {
                        $checksumFile = Join-Path $Directory 'zapfast-checksums.txt'
                        Receive-GuepardoFile -Uri $sums.browser_download_url -Destination $checksumFile -CacheDirectory $CacheDirectory -MaxAgeSeconds 0
                        @{ Uri=$asset.browser_download_url; Sha256=Get-GuepardoChecksumFromFile $checksumFile $asset.name; Destination=Join-Path $Directory 'zapfast.msi' }
                    }
                }
                'Composer.Composer' { @{ Uri='https://getcomposer.org/Composer-Setup.exe'; Sha256=''; Destination=Join-Path $Directory 'composer.exe' } }
            }
        } catch {
            Write-Warning "Cannot prepare download for $($pkg.Name); its installation will report the result. $_"
        }
    }
}
