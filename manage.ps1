[CmdletBinding()]
param([switch]$List,[switch]$Missing,[switch]$Installed,[switch]$InstallMissing,[string[]]$Apps,[string[]]$Profiles,[switch]$Plan,[switch]$Json,[switch]$NoColor)
$ErrorActionPreference='Stop'
if($Missing -and $Installed){throw 'Escolha -Missing ou -Installed, não ambos.'}
. (Join-Path $PSScriptRoot 'modules/installer/inventory.ps1')
. (Join-Path $PSScriptRoot 'modules/installer/ui.ps1')
$Apps=@($Apps | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Profiles=@($Profiles | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$catalog=Get-GuepardoCatalog
$themePath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Guepardo/manager-theme.txt'
$theme='system'
if(Test-Path -LiteralPath $themePath){$savedTheme=([IO.File]::ReadAllText($themePath)).Trim();if($savedTheme -in @('light','dark','system')){$theme=$savedTheme}}
$windowsProfiles=@($catalog.profiles | Where-Object { 'windows' -in $_.platforms } | ForEach-Object id)
foreach($profile in $Profiles) { if($profile -notin $windowsProfiles){throw "Perfil indisponível no Windows: $profile"} }
function Show-Inventory($rows) {
    $labels=@{installed='Instalado';missing='Faltando';configuration='Configuração';unknown='Não identificado'}
    $rows | Select-Object @{n='Estado';e={$labels[$_.Status]}},Name,Id,Detail | Format-Table -AutoSize -Wrap | Out-Host
}
:manager while($true) {
    $chosen=@()
    if(-not $Json){if($NoColor -or $env:NO_COLOR){Write-Host '  Verificando aplicativos do Windows...'}else{Write-Host '  Verificando aplicativos do Windows...' -ForegroundColor Cyan}}
    $inventory=@(Get-GuepardoWindowsInventory $catalog)
    $eligible=@(Select-GuepardoMissingInventory $inventory $Apps $Profiles)
    $shown=@($inventory | Where-Object { (-not $Profiles.Count -or @($_.Profiles | Where-Object {$_ -in $Profiles}).Count) -and (-not $Apps.Count -or $_.Id -in $Apps) -and (-not $Missing -or $_.Status -eq 'missing') -and (-not $Installed -or $_.Status -eq 'installed') })
    if($Json){ConvertTo-Json -InputObject @($shown) -Depth 5; exit 0}
    if($List -or $Missing -or $Installed){Show-Inventory $shown; exit 0}
    if($InstallMissing -or $Apps.Count -or $Plan) { $chosen=@($eligible.Id) }
    else {
        $accent=if($theme -eq 'light'){'DarkBlue'}elseif($theme -eq 'dark'){'Cyan'}else{[Console]::ForegroundColor}
        if($NoColor -or $env:NO_COLOR){Write-Host '  guepardo / gerenciar aplicativos'}else{Write-Host '  guepardo / gerenciar aplicativos' -ForegroundColor $accent}
        Write-Host "  $(@($shown | Where-Object Status -eq installed).Count) instalados | $($eligible.Count) faltando"
        Write-Host '  1 Ver todos | 2 Escolher faltantes | 3 Instalar todos os faltantes'
        Write-Host '  4 Ver instalados | R Atualizar | Q Sair'
        $themeLabel=@{light='Claro';dark='Escuro';system='Sistema'}[$theme]
        Write-Host "  Tema: $themeLabel | C Claro / E Escuro / S Sistema"
        $answer=Read-Host '  Escolha'
        switch($answer.ToLowerInvariant()) {
            'q' {exit 0}
            {$_ -in @('c','e','s')} {
                $theme=@{c='light';e='dark';s='system'}[$answer.ToLowerInvariant()]
                New-Item -ItemType Directory -Path (Split-Path $themePath) -Force | Out-Null
                [IO.File]::WriteAllText($themePath,$theme)
                continue manager
            }
            '1' {Show-Inventory $shown; Read-Host '  Enter para voltar' | Out-Null;continue manager}
            '4' {Show-Inventory @($shown | Where-Object Status -eq installed); Read-Host '  Enter para voltar' | Out-Null;continue manager}
            'r' {continue manager}
            '2' {
                if(-not $eligible.Count){Write-Host '  Nenhum aplicativo faltando nesta seleção.';continue manager}
                $selection=[pscustomobject]@{profiles=$catalog.profiles;apps=@($catalog.apps | Where-Object id -in $eligible.Id)}
                try {$chosen=@(Select-GuepardoApps $selection -NoColor:$NoColor)}catch [OperationCanceledException]{continue manager}
            }
            '3' {$chosen=@($eligible.Id)}
            default {Write-Host '  Escolha 1, 2, 3, R ou Q.';continue manager}
        }
    }
    if(-not $chosen.Count){Write-Host '  Nenhum aplicativo faltando nesta seleção. Nada foi instalado.';exit 0}
    Show-Inventory @($inventory | Where-Object Id -in $chosen)
    if(-not $Plan -and -not $InstallMissing -and -not $Apps.Count){
        if((Read-Host "  Instalar $($chosen.Count) aplicativo(s)? [s/N]") -notmatch '^[sS]$'){continue}
    }
    # The installer prepares PowerShell/UAC and resolves dependencies; no profile is rerun here.
    & (Join-Path $PSScriptRoot 'install.ps1') -Apps $chosen -Plan:$Plan -NoColor:$NoColor
    exit $LASTEXITCODE
}
