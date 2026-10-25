function Write-GuepardoHeading {
    param([string]$Text, [switch]$NoColor)
    if ($NoColor -or $env:NO_COLOR) { Write-Host "`n  $Text" }
    else { Write-Host "`n  $Text" -ForegroundColor Magenta }
}

function Select-GuepardoApps {
    param($Catalog, [switch]$NoColor)
    $selected = @{}; $expanded = @{}
    $profiles = @($Catalog.profiles | Where-Object { 'windows' -in $_.platforms })
    while ($true) {
        if (-not [Console]::IsOutputRedirected -and $env:TERM -ne 'dumb') { Clear-Host }
        Write-GuepardoHeading 'guepardo / prepare seu ambiente' -NoColor:$NoColor
        Write-Host '  Marque perfis ou expanda um perfil para escolher aplicativos.'
        $rows = @(); $number = 0
        foreach ($profile in $profiles) {
            $members = @($Catalog.apps | Where-Object { $profile.id -in $_.profiles })
            $count = @($members | Where-Object { $selected[$_.id] }).Count
            $number++; $rows += @{ Kind='profile'; Value=$profile; Members=$members }
            Write-Host ('  {0,2}  [{1}/{2}] {3}' -f $number,$count,$members.Count,$profile.label)
            if ($expanded[$profile.id]) {
                foreach ($app in $members) {
                    $number++; $rows += @{ Kind='app'; Value=$app }
                    $mark = if ($selected[$app.id]) { 'x' } else { ' ' }
                    Write-Host ('  {0,2}    [{1}] {2}' -f $number,$mark,$app.name)
                }
            }
        }
        Write-Host "`n  Número: marcar/desmarcar | e N: expandir perfil | t: todos | q: sair"
        $answer = Read-Host '  Enter para instalar'
        if ($answer -eq 'q') { throw [OperationCanceledException]::new('Instalação cancelada.') }
        if ($answer -eq '') {
            $ids = @($Catalog.apps | Where-Object { $selected[$_.id] } | ForEach-Object { $_.id })
            if ($ids.Count -gt 0) { return $ids }
            Write-Host '  Escolha ao menos um aplicativo.'; continue
        }
        if ($answer -eq 't') { foreach ($app in $Catalog.apps) { $selected[$app.id]=$true }; continue }
        if ($answer -match '^e\s+(\d+)$') {
            $n = [int]$Matches[1]-1
            if ($n -ge 0 -and $n -lt $rows.Count -and $rows[$n].Kind -eq 'profile') { $id=$rows[$n].Value.id; $expanded[$id] = -not $expanded[$id] }
            continue
        }
        $n=0
        if ([int]::TryParse($answer,[ref]$n) -and $n -gt 0 -and $n -le $rows.Count) {
            $row=$rows[$n-1]
            if ($row.Kind -eq 'app') { $selected[$row.Value.id] = -not $selected[$row.Value.id] }
            else {
                $all = @($row.Members | Where-Object { -not $selected[$_.id] }).Count -eq 0
                foreach ($app in $row.Members) { $selected[$app.id] = -not $all }
            }
        }
    }
}

function Write-GuepardoResult {
    param([string]$Name, [string]$Status, [string]$Detail, [switch]$NoColor)
    $line = '  {0,-18} {1}  {2}' -f $Status,$Name,$Detail
    if ($NoColor -or $env:NO_COLOR) { Write-Host $line; return }
    $color = switch ($Status) { 'concluído' {'Green'}; 'já instalado' {'DarkGray'}; 'falhou' {'Red'}; default {'Cyan'} }
    Write-Host $line -ForegroundColor $color
}
