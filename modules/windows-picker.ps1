#requires -Version 5.1
function Get-WindowsPickerItems {
    @(
        [pscustomobject]@{Id='cli';Label='CLI e servidor';Description='Git, gh e ferramentas de terminal.'},
        [pscustomobject]@{Id='dev';Label='Desenvolvimento';Description='Bun, uv, NVM e ferramentas de desenvolvimento.'},
        [pscustomobject]@{Id='web';Label='Stack web';Description='PHP, Composer e MySQL.'},
        [pscustomobject]@{Id='desktop';Label='Aplicativos do desktop';Description='Navegadores, editores, multimidia e utilitarios.'},
        [pscustomobject]@{Id='games';Label='Jogos e entretenimento';Description='Steam, Epic, GOG, Discord, Stremio e ferramentas de jogos.'},
        [pscustomobject]@{Id='jellyfin';Label='Jellyfin completo';Description='Servidor, tema GlassFin, banner Media Bar e plugins de metadados.'},
        [pscustomobject]@{Id='all';Label='Todos';Description='Inclui os seis modulos Windows, inclusive Jellyfin.'}
    )
}

function Switch-WindowsPickerItem {
    param([hashtable]$Selected, [string]$Id)
    $ids = @(Get-WindowsPickerItems | Where-Object {$_.Id -ne 'all'} | ForEach-Object {$_.Id})
    if ($Id -eq 'all') {
        $mark = @($ids | Where-Object {-not $Selected[$_]}).Count -gt 0
        foreach ($itemId in $ids) {$Selected[$itemId]=$mark}
    } elseif ($Id -in $ids) {
        $Selected[$Id] = -not $Selected[$Id]
    }
}

function Show-WindowsPicker {
    param([hashtable]$Selected, [int]$Focus, [string]$Message)
    $items = @(Get-WindowsPickerItems)
    $count = @($Selected.Keys | Where-Object {$Selected[$_]}).Count
    Write-Host 'guepardo' -ForegroundColor Magenta -NoNewline
    Write-Host '  /  prepare seu proximo ambiente'
    Write-Host ''
    Write-Host '[ Windows ]' -ForegroundColor Magenta
    Write-Host 'Aplicativos e configuracao para Windows via Winget.'
    Write-Host ''
    for ($i=0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $marked = $Selected[$item.Id]
        if ($item.Id -eq 'all') {$marked = $count -eq 6}
        $marker = [char]9675
        if ($marked) {$marker = [char]9679}
        $pointer = ' '
        if ($i -eq $Focus) {$pointer = [char]9656}
        $line = ' {0}  {1}  {2}  {3}' -f $pointer,($i+1),$marker,$item.Label
        if ($i -eq $Focus) {Write-Host $line.PadRight(48) -ForegroundColor White -BackgroundColor DarkMagenta}
        elseif ($marked) {Write-Host $line -ForegroundColor Cyan}
        else {Write-Host $line -ForegroundColor Gray}
    }
    Write-Host ''
    Write-Host "$count modulos selecionados" -ForegroundColor Magenta -NoNewline
    Write-Host '   Enter continuar'
    Write-Host 'Setas navegar / Espaco ou 1-7 selecionar / Q sair'
    Write-Host $items[$Focus].Description -ForegroundColor DarkGray
    if ($Message) {Write-Host $Message -ForegroundColor Yellow}
}

function Read-WindowsPickerKey {
    $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

function Select-WindowsProfiles {
    $items = @(Get-WindowsPickerItems)
    $selected = @{}
    $focus = 0
    $message = ''
    while ($true) {
        Clear-Host
        Show-WindowsPicker -Selected $selected -Focus $focus -Message $message
        try {$key=Read-WindowsPickerKey} catch {
            throw 'Menu requer terminal interativo. Para automacao, use install.cmd -Profiles jellyfin ou outros perfis.'
        }
        $message = ''
        switch ($key.VirtualKeyCode) {
            38 {$focus=($focus+$items.Count-1)%$items.Count}
            40 {$focus=($focus+1)%$items.Count}
            32 {Switch-WindowsPickerItem -Selected $selected -Id $items[$focus].Id}
            13 {
                $profiles=@($items | Where-Object {$_.Id -ne 'all' -and $selected[$_.Id]} | ForEach-Object {$_.Id})
                if ($profiles.Count) {Clear-Host; return ($profiles -join ',')}
                $message = 'Selecione ao menos um modulo para continuar.'
            }
            27 {Clear-Host; return $null}
            81 {Clear-Host; return $null}
            default {
                $number = [string]$key.Character
                if ($number -match '^[1-7]$') {
                    $focus = [int]::Parse($number)-1
                    Switch-WindowsPickerItem -Selected $selected -Id $items[$focus].Id
                }
            }
        }
    }
}
