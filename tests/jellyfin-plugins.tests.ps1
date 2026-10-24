#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules/jellyfin.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
$script:repository = 'https://repo.jellyfin.org/files/plugin/manifest.json'
$script:repositories = @([pscustomobject]@{ Name = 'Other'; Url = 'https://example.com/plugins.json'; Enabled = $true })
$script:installed = @()
$script:calls = @()
$script:failName = ''
$script:catalog = @()
$names = @('AniDB','AniList','AniSearch','Kitsu','Artwork','Cover Art Archive')
foreach ($name in $names) {
    $script:catalog += [pscustomobject]@{
        Name = $name; Guid = [Guid]::NewGuid().ToString()
        Versions = @(
            [pscustomobject]@{ Version = '99.0.0.0'; TargetAbi = '12.0.0.0'; RepositoryUrl = $script:repository },
            [pscustomobject]@{ Version = '3.0.0.0'; TargetAbi = '10.11.0.0'; RepositoryUrl = 'https://example.com/plugins.json' },
            [pscustomobject]@{ Version = '2.0.0.0'; TargetAbi = '10.11.0.0'; RepositoryUrl = $script:repository }
        )
    }
}
function Invoke-JellyfinRequest {
    param($BaseUrl, $Path, $Method = 'GET', $Headers, $Body, $RequestTimeout)
    switch ($Path) {
        'Repositories' {
            if ($Method -eq 'POST') { $script:repositories = $Body; return }
            return $script:repositories
        }
        'Packages' { return $script:catalog }
        'Plugins' { return $script:installed }
        default {
            if ($Path -notlike 'Packages/Installed/*') { throw "Unexpected: $Path" }
            $script:calls += $Path
            if ($script:failName -and $Path -like "Packages/Installed/$($script:failName)?*") { throw 'Simulated download failure' }
            Assert ($Path -like '*version=2.0.0.0*') 'seleciona versao compativel do repositorio oficial'
            Assert ($Path -like '*repositoryUrl=https%3A%2F%2Frepo.jellyfin.org*') 'usa repositorio oficial explicitamente'
        }
    }
}
Install-JellyfinPlugins -BaseUrl 'http://localhost:8096' -Headers @{} -ServerVersion '10.11.1'
Assert ($script:calls.Count -eq 6) 'instala seis plugins'
Assert ($script:repositories.Count -eq 2 -and $script:repositories[0].Name -eq 'Other') 'preserva outros repositorios'
Assert ($script:calls[-1] -like 'Packages/Installed/Cover%20Art%20Archive?*') 'escapa nomes na URL'
foreach ($package in $script:catalog) {
    $script:installed += [pscustomobject]@{ Id = $package.Guid; Version = '2.0.0.0'; Status = 'Active' }
}
Install-JellyfinPlugins -BaseUrl 'http://localhost:8096' -Headers @{} -ServerVersion '10.11.1'
Assert ($script:calls.Count -eq 6) 'nao reinstala plugins presentes'
$script:installed = @()
$script:failName = 'AniList'
$failed = $false
try { Install-JellyfinPlugins -BaseUrl 'http://localhost:8096' -Headers @{} -ServerVersion '10.11.1' } catch { $failed = $_.Exception.Message -like '*AniList*' }
Assert ($failed -and $script:calls.Count -eq 12) 'continua demais plugins e informa falha parcial'
$script:failName = ''
$failed = $false
try { Install-JellyfinPlugins -BaseUrl 'http://localhost:8096' -Headers @{} -ServerVersion '10.10.0' } catch { $failed = $_.Exception.Message -like '*Falha ao instalar plugins*' }
Assert ($failed -and $script:calls.Count -eq 12) 'nao instala versoes incompativeis'
Write-Host 'PASS: seis plugins, compatibilidade, repositorio oficial, idempotencia e falhas parciais.'
