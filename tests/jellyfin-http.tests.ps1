#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules/jellyfin.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
$script:bodyJson = $null
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $TimeoutSec, $ContentType, $Body, $ErrorAction)
    if ($Method -eq 'POST') { $script:bodyJson = [Text.Encoding]::UTF8.GetString($Body); return }
    $response = @([pscustomobject]@{Name='AniDB'}, [pscustomobject]@{Name='AniList'})
    Write-Output -NoEnumerate $response
}
$catalog = @(Invoke-JellyfinRequest -BaseUrl 'http://localhost:8096' -Path 'Packages')
Assert ($catalog.Count -eq 2 -and $catalog[0].Name -eq 'AniDB') 'enumera array JSON emitido como um item pelo Invoke-RestMethod'
Invoke-JellyfinRequest -BaseUrl 'http://localhost:8096' -Path 'Repositories' -Method POST -Body @([pscustomobject]@{Name='Official'})
Assert ($script:bodyJson.StartsWith('[')) 'preserva array JSON de um repositorio'
Write-Host 'PASS: transporte HTTP preserva listas de plugins e arrays JSON unitarios.'
