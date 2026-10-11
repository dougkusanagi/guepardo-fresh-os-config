#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules/jellyfin.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
$script:manifest = @()
foreach ($name in @('File Transformation','Media Bar')) {
    $script:manifest += [pscustomobject]@{Name=$name; Guid=[Guid]::NewGuid().ToString(); Versions=@(
        [pscustomobject]@{Version='3.0.0.0';TargetAbi='10.11.11.0';SourceUrl='https://example.com/wrong10.zip'},
        [pscustomobject]@{Version='3.0.0.0';TargetAbi='12.0.0.0';SourceUrl='https://example.com/wrong12.zip'},
        [pscustomobject]@{Version='3.0.0.0';TargetAbi='12.1.0.0';SourceUrl='https://example.com/correct.zip'}
    )}
}
$selected = @(Select-JellyfinBannerManifest -Manifest $script:manifest -ServerVersion '12.1.0')
Assert ($selected.Count -eq 2 -and $selected[0].Versions.Count -eq 1 -and $selected[0].Versions[0].SourceUrl -like '*correct.zip') 'seleciona ZIP da linha exata, mesmo com versoes repetidas'
Assert ($script:manifest[0].Versions.Count -eq 3) 'preserva manifesto original'
$failed = $false
try { Select-JellyfinBannerManifest -Manifest $script:manifest -ServerVersion '12.2.0' } catch {$failed=$true}
Assert $failed 'recusa linha sem pacote'
function Invoke-RestMethod { param($Uri,$TimeoutSec,$ErrorAction); return $script:manifest }
$script:original = @([pscustomobject]@{Name='Existing';Url='https://example.com/existing.json';Enabled=$true})
$script:repos = $script:original
function Invoke-JellyfinRequest {
    param($BaseUrl,$Path,$Headers,$Method,$Body)
    if($Method -eq 'POST') {$script:repos=$Body;return}
    return $script:repos
}
$script:installFailure = $false
$script:feedUrl = $null
function Install-JellyfinPlugins {
    param($BaseUrl,$Headers,$ServerVersion,$Required,$Repository)
    Assert ($Required[0] -eq 'File Transformation' -and $Required[1] -eq 'Media Bar') 'instala dependencia antes do banner'
    $script:feedUrl=$Repository
    $web=[Net.WebClient]::new()
    try {$feed=$web.DownloadString($Repository) | ConvertFrom-Json} finally {$web.Dispose()}
    Assert ($feed.Count -eq 2 -and $feed[0].Versions[0].TargetAbi -eq '12.1.0.0') 'catalogo loopback serve apenas pacotes corretos'
    if($script:installFailure) {throw 'simulated failure'}
}
Install-JellyfinBanner -BaseUrl 'http://localhost:8096' -Headers @{} -ServerVersion '12.1.0'
Assert ($script:repos.Count -eq 1 -and $script:repos[0].Url -eq $script:original[0].Url) 'restaura repositorios ao terminar'
$script:installFailure=$true
$failed=$false
try {Install-JellyfinBanner -BaseUrl 'http://localhost:8096' -Headers @{} -ServerVersion '12.1.0'} catch {$failed=$true}
Assert ($failed -and $script:repos.Count -eq 1) 'restaura repositorios mesmo em falha'
Write-Host 'PASS: banner, dependencia, ABI exata, catalogo loopback e limpeza em falhas.'
