. (Join-Path $PSScriptRoot 'catalog.ps1')
. (Join-Path $PSScriptRoot 'providers.ps1')

function Get-GuepardoWindowsInventory {
    param($Catalog=(Get-GuepardoCatalog))
    # Query Winget once, rather than starting it for every application.
    $registered='';$wingetOk=$false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $saved=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            $registered=& winget list --disable-interactivity --accept-source-agreements 2>&1 | Out-String
            $wingetOk=$LASTEXITCODE -eq 0
        } finally { $ErrorActionPreference=$saved }
    }
    foreach($app in $Catalog.apps | Where-Object { $_.windows }) {
        $package=@{Id=$app.id;Definition=$app}
        $status='missing';$provider='';$detail=''
        if ($app.id -in @('guepardo.dotagents','guepardo.jellyfin-config','guepardo.wsl2')) {
            $status='configuration';$detail='Etapa de configuração; use o instalador para reaplicar.'
        } else {
            $commands=@($app.windows.commands)
            $usable=$commands.Count -gt 0
            foreach($command in $commands) { if(-not(Get-GuepardoCommand $command)){ $usable=$false } }
            $managedRuntime=$false
            if($app.id -eq 'Microsoft.PowerShell' -and -not $usable) {
                $runtimeRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Guepardo/Runtime/PowerShell'
                if(Test-Path -LiteralPath $runtimeRoot) {
                    $managedRuntime=@(Get-ChildItem -LiteralPath $runtimeRoot -Directory | Where-Object {
                        (Test-Path -LiteralPath (Join-Path $_.FullName 'pwsh.exe')) -and (Test-Path -LiteralPath (Join-Path $_.FullName '.verified'))
                    }).Count -gt 0
                    if($managedRuntime){$usable=$true}
                }
            }
            $scoopRegistered=$app.windows.scoop -and (Test-Path -LiteralPath (Join-Path (Get-GuepardoScoopRoot) "apps/$($app.windows.scoop)/current") -PathType Container)
            $wingetRegistered=$wingetOk -and $registered -match ('(?im)(?:^|\s)'+[regex]::Escape($app.id)+'(?:\s|$)')
            if ($app.windows.provider -eq 'custom') {
                $usable=Test-GuepardoPackage $package custom
            }
            if ($usable -or (($scoopRegistered -or $wingetRegistered) -and $commands.Count -eq 0)) {
                $status='installed';$provider=if($managedRuntime){'Runtime Guepardo'}elseif($scoopRegistered){'Scoop'}elseif($wingetRegistered){'Winget'}else{'Sistema'}
            } elseif ($scoopRegistered -or $wingetRegistered) {
                $detail='Registrado, mas o comando não está disponível; precisa de reparo.'
            } elseif (-not $wingetOk -and $commands.Count -eq 0 -and $app.windows.provider -ne 'custom') {
                $status='unknown';$detail='Não foi possível consultar o registro do Winget.'
            }
        }
        [pscustomobject]@{Id=$app.id;Name=$app.name;Status=$status;Provider=$provider;Profiles=@($app.profiles);Detail=$detail}
    }
}

function Select-GuepardoMissingInventory {
    param([object[]]$Inventory,[string[]]$Apps,[string[]]$Profiles)
    foreach($id in $Apps) { if($id -notin $Inventory.Id){throw "Aplicativo desconhecido: $id"} }
    @($Inventory | Where-Object {
        $_.Status -eq 'missing' -and (-not $Apps.Count -or $_.Id -in $Apps) -and
        (-not $Profiles.Count -or @($_.Profiles | Where-Object { $_ -in $Profiles }).Count -gt 0)
    })
}
