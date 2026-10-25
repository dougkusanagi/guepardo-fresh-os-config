$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../modules/installer/download.ps1')
function Assert($condition,$message) { if(-not $condition) { throw $message } }
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-http-'+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
$process=$null
try {
    $node=(Get-Command node -CommandType Application).Source
    $fixture=Join-Path $PSScriptRoot 'fixtures/download-server.cjs'; $portFile=Join-Path $sandbox 'port'
    $start=@{FilePath=$node;ArgumentList=@(('"'+$fixture+'"'),('"'+$portFile+'"'));PassThru=$true}
    if ($env:OS -eq 'Windows_NT') { $start.WindowStyle='Hidden' }
    $process=Start-Process @start
    for($n=0;$n -lt 100 -and -not (Test-Path $portFile);$n++) { Start-Sleep -Milliseconds 100 }
    if(-not (Test-Path $portFile)) { throw 'Fixture server failed to start' }
    $base='http://127.0.0.1:'+(Get-Content $portFile -Raw).Trim()
    $cache=Join-Path $sandbox 'cache'; $out=Join-Path $sandbox 'download'
    $fixtureFile=Join-Path $sandbox 'expected'; [IO.File]::WriteAllBytes($fixtureFile,([byte[]](0..131071 | ForEach-Object {71})))
    $sha=(Get-FileHash $fixtureFile -Algorithm SHA256).Hash
    Receive-GuepardoFile "$base/file" $out -Sha256 $sha -CacheDirectory $cache
    Receive-GuepardoFile "$base/file" $out -Sha256 $sha -CacheDirectory $cache
    $stats=Invoke-RestMethod "$base/stats"
    Assert ($stats.counts.'/file' -eq 1) 'Cache caused another network download'
    $entry=Get-ChildItem $cache -File | Where-Object {$_.Name -match '^[a-f0-9]{64}$'} | Select-Object -First 1
    Set-Content -LiteralPath $entry.FullName 'corrupt'
    Receive-GuepardoFile "$base/file" $out -Sha256 $sha -CacheDirectory $cache
    Assert ((Get-FileHash $out).Hash -eq $sha) 'Corrupt cache was trusted'
    Receive-GuepardoFile "$base/resume" $out -Sha256 $sha -CacheDirectory $cache
    Assert ((Get-FileHash $out).Hash -eq $sha) 'Interrupted download did not resume correctly'
    $badAccepted=$false
    try { Receive-GuepardoFile "$base/bad" $out -Sha256 $sha -CacheDirectory $cache -Attempts 1; $badAccepted=$true } catch {}
    Assert (-not $badAccepted -and (Get-FileHash $out).Hash -eq $sha) 'Bad checksum replaced existing destination'
    $downloads=@(
        @{Uri="$base/delay?a";Destination=(Join-Path $sandbox 'a');Sha256=$sha},
        @{Uri="$base/delay?b";Destination=(Join-Path $sandbox 'b');Sha256=$sha}
    )
    Invoke-GuepardoPrefetch $downloads $cache -Jobs 2
    $stats=Invoke-RestMethod "$base/stats"
    Assert ($stats.peak -ge 2) 'Independent transfers were not concurrent'
    Assert ((Get-FileHash (Join-Path $sandbox 'a')).Hash -eq $sha) 'Parallel download was corrupted'
    Write-Host 'PASS: real HTTP cache, corrupt cache recovery, interrupted transfer, checksum rejection and parallel downloads.'
} finally {
    if($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    Remove-Item -LiteralPath $sandbox -Recurse -Force
}
exit 0
