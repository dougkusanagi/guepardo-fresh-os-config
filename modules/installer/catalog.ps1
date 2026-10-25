function Get-GuepardoCatalog {
    param([string]$Path = (Join-Path $PSScriptRoot '../../catalog/apps.json'))
    $catalog = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($catalog.schemaVersion -ne 1) { throw 'Unsupported application catalog version.' }
    $ids = @{}
    foreach ($app in $catalog.apps) {
        if (-not $app.id -or $ids.ContainsKey($app.id)) { throw "Duplicate or empty app ID: $($app.id)" }
        $ids[$app.id] = $app
    }
    foreach ($app in $catalog.apps) {
        foreach ($dependency in $app.dependsOn) {
            if (-not $ids.ContainsKey($dependency)) { throw "Unknown dependency: $dependency" }
        }
    }
    return $catalog
}

function Resolve-GuepardoPlan {
    param($Catalog, [string[]]$Profiles, [string[]]$Apps, [string[]]$ExcludeApps)
    $byId = @{}; foreach ($app in $Catalog.apps) { $byId[$app.id] = $app }
    foreach ($id in @($Apps) + @($ExcludeApps)) {
        if ($id -and -not $byId.ContainsKey($id)) { throw "Unknown app: $id" }
    }
    $selected = @($Catalog.apps | Where-Object {
        $appProfiles = $_.profiles
        ($Apps.Count -gt 0 -and $_.id -in $Apps) -or
        ($Apps.Count -eq 0 -and @($Profiles | Where-Object { $_ -in $appProfiles }).Count -gt 0)
    } | Where-Object { $_.id -notin $ExcludeApps })
    $ordered = New-Object System.Collections.ArrayList
    $visiting = @{}; $visited = @{}
    function Visit-GuepardoApp($id) {
        if ($visited[$id]) { return }
        if ($visiting[$id]) { throw "Dependency cycle: $id" }
        if ($id -in $ExcludeApps) { throw "Required dependency was excluded: $id" }
        $visiting[$id] = $true
        foreach ($dependency in $byId[$id].dependsOn) { Visit-GuepardoApp $dependency }
        $visiting.Remove($id)
        $visited[$id] = $true
        [void]$ordered.Add($byId[$id])
    }
    foreach ($app in $selected) { Visit-GuepardoApp $app.id }
    foreach ($app in $ordered) {
        @{ Id = $app.id; Name = $app.name; Definition = $app; DependsOn = @($app.dependsOn) }
    }
}
