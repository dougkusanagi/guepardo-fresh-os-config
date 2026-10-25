function Write-GuepardoHeading {
    param([string]$Text, [switch]$NoColor)
    if ($NoColor -or $env:NO_COLOR) { Write-Host "`n  $Text" }
    else { Write-Host "`n  $Text" -ForegroundColor Magenta }
}

function Select-GuepardoAppsPlain {
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

function Get-GuepardoPickerRows {
    param($Catalog, $Selected, $Expanded)
    foreach ($profile in @($Catalog.profiles | Where-Object { 'windows' -in $_.platforms })) {
        $members = @($Catalog.apps | Where-Object { $profile.id -in $_.profiles })
        $count = @($members | Where-Object { $Selected[$_.id] }).Count
        $mark = if ($count -eq 0) { '[ ]' } elseif ($count -eq $members.Count) { '[x]' } else { '[-]' }
        $fold = if ($Expanded[$profile.id]) { '-' } else { '+' }
        @{Kind='profile'; Profile=$profile.id; Members=$members; Text="$mark $fold $($profile.label)  ($count/$($members.Count))"}
        if ($Expanded[$profile.id]) {
            foreach ($app in $members) {
                $mark = if ($Selected[$app.id]) { '[x]' } else { '[ ]' }
                @{Kind='app'; Profile=$profile.id; App=$app; Text="    $mark $($app.name)"}
            }
        }
    }
}

function Get-GuepardoPickerViewport {
    param([int]$Count, [int]$Active, [int]$Height)
    $capacity = [Math]::Max(1,$Height-11)
    $first = [Math]::Max(0,[Math]::Min($Active-[int]($capacity/2),$Count-$capacity))
    @{First=$first;Last=[Math]::Min($Count-1,$first+$capacity-1)}
}

function Write-GuepardoPicker {
    param([object[]]$Rows, [int]$Active, [int]$Height, [int]$Width, [int]$Count, [string]$Message, [switch]$NoColor)
    if (-not [Console]::IsOutputRedirected) { Clear-Host }
    if ($Width -lt 60) {
        Write-GuepardoHeading 'guepardo / apps' -NoColor:$NoColor
        Write-Host '  Escolha os apps.'
    } else {
        Write-GuepardoHeading 'guepardo / prepare seu ambiente' -NoColor:$NoColor
        Write-Host '  Escolha os perfis e aplicativos deste computador.'
    }
    Write-Host ''
    $view = Get-GuepardoPickerViewport $Rows.Count $Active $Height
    for ($i=$view.First; $i -le $view.Last; $i++) {
        $cursor = if ($i -eq $Active) { '>' } else { ' ' }
        $line = "  $cursor $($Rows[$i].Text)"
        $limit = [Math]::Max(10,$Width-1)
        if ($line.Length -gt $limit) { $line=$line.Substring(0,$limit-3)+'...' }
        if ($i -eq $Active -and -not $NoColor -and -not $env:NO_COLOR) { Write-Host $line -ForegroundColor White -BackgroundColor DarkMagenta }
        else { Write-Host $line }
    }
    if ($Width -lt 75) {
        Write-Host "`n  $Count apps marcados"
        Write-Host '  Setas: navegar'
        Write-Host '  Espaco: marcar'
        Write-Host '  <-/->: expandir'
        Write-Host '  Enter: OK | Q: sair'
    } else {
        Write-Host "`n  $Count aplicativos selecionados"
        Write-Host '  Setas: navegar | Espaco: marcar | Direita/esquerda: expandir/recolher'
        Write-Host '  Enter: continuar | T: todos/nenhum | Esc ou Q: cancelar'
    }
    if ($Message) { Write-Host "  $Message" }
}

function Select-GuepardoApps {
    param($Catalog, [switch]$NoColor, [scriptblock]$ReadKey)
    # Read-Host remains only for terminals without raw keyboard input.
    if (-not $ReadKey -and ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or $env:TERM -eq 'dumb')) {
        return Select-GuepardoAppsPlain -Catalog $Catalog -NoColor:$NoColor
    }
    $selected=@{}; $expanded=@{}; $active=0; $message=''
    $cursorVisible=$null
    try {
        if (-not [Console]::IsOutputRedirected) {
            try { $cursorVisible=[Console]::CursorVisible; [Console]::CursorVisible=$false } catch {}
        }
        while ($true) {
            $rows=@(Get-GuepardoPickerRows $Catalog $selected $expanded)
            if ($rows.Count -eq 0) { throw 'Nenhum aplicativo disponível neste catálogo.' }
            $active=[Math]::Max(0,[Math]::Min($active,$rows.Count-1))
            $height=30; $width=90
            try { if ([Console]::WindowHeight -gt 0) { $height=[Console]::WindowHeight }; if ([Console]::WindowWidth -gt 0) { $width=[Console]::WindowWidth } } catch {}
            $count=@($Catalog.apps | Where-Object { $selected[$_.id] }).Count
            Write-GuepardoPicker -Rows $rows -Active $active -Height $height -Width $width -Count $count -Message $message -NoColor:$NoColor
            $key = if ($ReadKey) { & $ReadKey } else { [Console]::ReadKey($true) }
            if ($null -eq $key) { throw [OperationCanceledException]::new('Entrada encerrada.') }
            $row=$rows[$active]; $message=''
            switch ([string]$key.Key) {
                'UpArrow' { $active=($active+$rows.Count-1)%$rows.Count }
                'DownArrow' { $active=($active+1)%$rows.Count }
                'Home' { $active=0 }
                'End' { $active=$rows.Count-1 }
                'PageUp' { $active=[Math]::Max(0,$active-[Math]::Max(1,$height-11)) }
                'PageDown' { $active=[Math]::Min($rows.Count-1,$active+[Math]::Max(1,$height-11)) }
                'RightArrow' { if ($row.Kind -eq 'profile') { $expanded[$row.Profile]=$true } }
                'LeftArrow' {
                    $expanded[$row.Profile]=$false
                    for ($i=$active; $i -ge 0; $i--) { if ($rows[$i].Kind -eq 'profile' -and $rows[$i].Profile -eq $row.Profile) { $active=$i; break } }
                }
                'Spacebar' {
                    if ($row.Kind -eq 'app') { $selected[$row.App.id] = -not $selected[$row.App.id] }
                    else {
                        $all=@($row.Members | Where-Object { -not $selected[$_.id] }).Count -eq 0
                        foreach ($app in $row.Members) { $selected[$app.id] = -not $all }
                    }
                }
                'T' {
                    $all=@($Catalog.apps | Where-Object { -not $selected[$_.id] }).Count -eq 0
                    foreach ($app in $Catalog.apps) { $selected[$app.id] = -not $all }
                }
                'Enter' {
                    $ids=@($Catalog.apps | Where-Object { $selected[$_.id] } | ForEach-Object { $_.id })
                    if ($ids.Count -gt 0) { return $ids }
                    $message='Escolha ao menos um aplicativo para continuar.'
                }
                'Escape' { throw [OperationCanceledException]::new('Instalação cancelada.') }
                'Q' { throw [OperationCanceledException]::new('Instalação cancelada.') }
            }
        }
    } finally {
        if ($null -ne $cursorVisible) { try { [Console]::CursorVisible=$cursorVisible } catch {} }
    }
}

function Write-GuepardoResult {
    param([string]$Name, [string]$Status, [string]$Detail, [switch]$NoColor)
    $line = '  {0,-18} {1}  {2}' -f $Status,$Name,$Detail
    if ($NoColor -or $env:NO_COLOR) { Write-Host $line; return }
    $color = switch ($Status) { 'concluído' {'Green'}; 'já instalado' {'DarkGray'}; 'falhou' {'Red'}; default {'Cyan'} }
    Write-Host $line -ForegroundColor $color
}
