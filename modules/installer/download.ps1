function Receive-GuepardoFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [string]$Sha256,
        [string]$CacheDirectory = (Join-Path $env:LOCALAPPDATA 'Guepardo/Cache'),
        [ValidateRange(1,10)][int]$Attempts = 3,
        [ValidateRange(1,86400)][int]$TimeoutSeconds = 600,
        [ValidateRange(0,86400)][int]$MaxAgeSeconds = 86400
    )
    if (([uri]$Uri).Scheme -ne 'https' -and -not ([uri]$Uri).IsLoopback) { throw 'Downloads require HTTPS.' }
    if ($Sha256 -and $Sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid SHA256.' }
    New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$Uri|$Sha256")))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $cached = Join-Path $CacheDirectory $key
    $partial = "$cached.part"; $metadata = "$cached.json"
    $lock = $null
    try {
        $lock = [IO.File]::Open("$cached.lock", 'OpenOrCreate', 'ReadWrite', 'None')
        if ((Test-Path -LiteralPath $cached) -and (Test-Path -LiteralPath $metadata)) {
            try {
                $record = Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
                $actual = (Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash
                $fresh = $Sha256 -or (([DateTime]::UtcNow - [DateTime]::Parse($record.downloadedAt).ToUniversalTime()).TotalSeconds -lt $MaxAgeSeconds)
                if ($fresh -and $actual -eq $record.sha256 -and (-not $Sha256 -or $actual -eq $Sha256)) {
                    New-Item -ItemType Directory -Path (Split-Path ([IO.Path]::GetFullPath($Destination))) -Force | Out-Null
                    Copy-Item -LiteralPath $cached -Destination $Destination -Force
                    $script:GuepardoLastTransfer = @{ CacheHit=$true }
                    Write-Verbose "Cache: $Uri"
                    return
                }
            } catch { Write-Verbose "Ignoring invalid cache: $_" }
        }
        # Mutable URLs without an upstream checksum cannot safely reuse partial content.
        if (-not $Sha256 -and (Test-Path -LiteralPath $partial)) { Remove-Item -LiteralPath $partial -Force }
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (-not $curl) { $curl = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue }
        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                if ($curl) {
                    $arguments = @('--fail','--location','--silent','--show-error','--connect-timeout','20','--max-time',"$TimeoutSeconds",'--speed-time','45','--speed-limit','1024','--output',$partial)
                    if (Test-Path -LiteralPath $partial) { $arguments += @('--continue-at','-') }
                    $savedErrors = $ErrorActionPreference
                    try {
                        $ErrorActionPreference = 'Continue'
                        $diagnostic = @(& $curl.Source @arguments $Uri 2>&1)
                        $code = $LASTEXITCODE
                    } finally { $ErrorActionPreference = $savedErrors }
                    if ($code -in @(22,33,36)) {
                        # Range refused or partial no longer valid: restart this transfer.
                        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
                    }
                    if ($code -ne 0) { throw "Download failed ($code): $Uri $($diagnostic -join ' ')" }
                } else {
                    $oldProgress = $ProgressPreference
                    try { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $partial -TimeoutSec $TimeoutSeconds -ErrorAction Stop }
                    finally { $ProgressPreference = $oldProgress }
                }
                $actual = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
                if ($Sha256 -and $actual -ne $Sha256) {
                    Remove-Item -LiteralPath $partial -Force
                    throw "SHA256 mismatch: $Uri"
                }
                Move-Item -LiteralPath $partial -Destination $cached -Force
                @{ uri=$Uri; sha256=$actual; downloadedAt=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $metadata -Encoding UTF8
                New-Item -ItemType Directory -Path (Split-Path ([IO.Path]::GetFullPath($Destination))) -Force | Out-Null
                Copy-Item -LiteralPath $cached -Destination $Destination -Force
                $script:GuepardoLastTransfer = @{ CacheHit=$false }
                return
            } catch {
                if ($attempt -eq $Attempts) { throw }
                Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2,$attempt-1)))
            }
        }
    } finally { if ($lock) { $lock.Dispose() } }
}

function Invoke-GuepardoPrefetch {
    param([object[]]$Downloads, [string]$CacheDirectory, [ValidateRange(1,8)][int]$Jobs = 4)
    $running = New-Object System.Collections.ArrayList
    $index = 0; $done = 0
    try {
        while ($index -lt $Downloads.Count -or $running.Count -gt 0) {
            while ($index -lt $Downloads.Count -and $running.Count -lt $Jobs) {
                $item = $Downloads[$index++]
                $job = Start-Job -ScriptBlock {
                    param($module, $item, $cache)
                    $ErrorActionPreference = 'Stop'
                    . $module
                    $start = [DateTime]::UtcNow
                    Receive-GuepardoFile -Uri $item.Uri -Destination $item.Destination -Sha256 $item.Sha256 -CacheDirectory $cache
                    @{ File=[IO.Path]::GetFileName($item.Destination); Bytes=(Get-Item -LiteralPath $item.Destination).Length; Seconds=([DateTime]::UtcNow-$start).TotalSeconds; CacheHit=$script:GuepardoLastTransfer.CacheHit }
                } -ArgumentList (Join-Path $PSScriptRoot 'download.ps1'), $item, $CacheDirectory
                [void]$running.Add($job)
            }
            $finished = Wait-Job -Job @($running.ToArray()) -Any -Timeout 1
            if ($finished) {
                foreach ($result in @(Receive-Job -Job $finished -ErrorAction Stop)) {
                    if ($null -ne $result.Bytes) {
                        if ($result.CacheHit) { Write-Host ('  cache verificado  {0}  {1:N1} MB' -f $result.File,($result.Bytes/1MB)) }
                        else { Write-Host ('  download concluído  {0}  {1:N1} MB  {2:N1} MB/s' -f $result.File,($result.Bytes/1MB),($result.Bytes/1MB/[Math]::Max(.01,$result.Seconds))) }
                    }
                }
                if ($finished.State -ne 'Completed') { throw 'Prefetch job failed.' }
                [void]$running.Remove($finished)
                Remove-Job -Job $finished
                $done++
            }
            Write-Progress -Activity 'Preparando downloads' -Status "$done/$($Downloads.Count) concluídos; $($running.Count) em andamento" -PercentComplete ([int](100*$done/[Math]::Max(1,$Downloads.Count)))
        }
    } finally {
        foreach ($job in $running) { Stop-Job -Job $job; Remove-Job -Job $job -Force }
        Write-Progress -Activity 'Preparando downloads' -Completed
    }
}
