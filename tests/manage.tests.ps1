$ErrorActionPreference='Stop'
. "$PSScriptRoot/../modules/installer/inventory.ps1"
function Assert($ok,$message) {if(-not $ok){throw $message}}
$script:calls=0;$script:wingetCode=0
function winget { $script:calls++;'Registered Vendor.Registered 1.0';$global:LASTEXITCODE=$script:wingetCode }
function Get-Command {param($Name,$ErrorAction) if($Name -eq 'winget'){return @{Name='winget'}};return $null}
function Get-GuepardoCommand {param($Name) if($Name -eq 'present'){return @{Name='present'}};return $null}
function Get-GuepardoScoopRoot {return (Join-Path ([IO.Path]::GetTempPath()) ('missing-scoop-'+[guid]::NewGuid()))}
$catalog=[pscustomobject]@{apps=@(
    [pscustomobject]@{id='Vendor.Present';name='Present';profiles=@('cli');windows=@{commands=@('present');provider='winget'}},
    [pscustomobject]@{id='Vendor.Missing';name='Missing';profiles=@('cli');windows=@{commands=@('absent');provider='winget'}},
    [pscustomobject]@{id='Vendor.Registered';name='Registered';profiles=@('desktop');windows=@{commands=@();provider='winget'}},
    [pscustomobject]@{id='guepardo.jellyfin-config';name='Configuration';profiles=@('jellyfin');windows=@{commands=@();provider='custom'}}
)}
$rows=@(Get-GuepardoWindowsInventory $catalog)
Assert ($script:calls -eq 1) 'Winget queried more than once'
Assert ($rows[0].Status -eq 'installed' -and $rows[2].Status -eq 'installed') 'Installed binary/registered GUI app missed'
Assert ($rows[3].Status -eq 'configuration') 'Configuration treated as missing app'
$chosen=@(Select-GuepardoMissingInventory $rows @() @())
Assert ($chosen.Count -eq 1 -and $chosen[0].Id -eq 'Vendor.Missing') 'Bulk selection included installed/configuration apps'
Assert (@(Select-GuepardoMissingInventory $rows @('Vendor.Present') @()).Count -eq 0) 'Installed explicit app reinstalled'
Assert (@(Select-GuepardoMissingInventory $rows @() @('desktop')).Count -eq 0) 'Profile filter ignored'
$thrown=$false;try {Select-GuepardoMissingInventory $rows @('unknown') @()}catch{$thrown=$true};Assert $thrown 'Unknown app accepted'
$script:wingetCode=1;$rows=@(Get-GuepardoWindowsInventory $catalog)
Assert ($rows[2].Status -eq 'unknown') 'Failed inventory presented as missing GUI app'
# Parse and exercise the public read-only entry point in a fresh process.
$shell=(Get-Process -Id $PID).Path
$json=& $shell -NoProfile -File "$PSScriptRoot/../manage.ps1" -Json -Profiles games
Assert ($LASTEXITCODE -eq 0 -and @($json | ConvertFrom-Json).Count -gt 0) 'Public inventory JSON failed'
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-manage-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path (Join-Path $sandbox 'modules/installer') -Force | Out-Null
try {
    Copy-Item -LiteralPath "$PSScriptRoot/../manage.ps1" -Destination (Join-Path $sandbox 'manage.ps1')
    @'
function Get-GuepardoCatalog { [pscustomobject]@{profiles=@([pscustomobject]@{id='cli'});apps=@()} }
function Get-GuepardoWindowsInventory {
    [pscustomobject]@{Id='present';Name='Present';Status='installed';Profiles=@('cli');Detail=''}
    [pscustomobject]@{Id='absent';Name='Absent';Status='missing';Profiles=@('cli');Detail=''}
    [pscustomobject]@{Id='config';Name='Configuration';Status='configuration';Profiles=@('cli');Detail=''}
}
function Select-GuepardoMissingInventory {param($Inventory,$Apps,$Profiles) @($Inventory | Where-Object Status -eq missing) }
'@ | Set-Content -LiteralPath (Join-Path $sandbox 'modules/installer/inventory.ps1')
    Set-Content -LiteralPath (Join-Path $sandbox 'modules/installer/ui.ps1') -Value 'function Write-GuepardoHeading {param($Text,[switch]$NoColor)}'
    @'
param([string[]]$Apps,[switch]$Plan,[switch]$NoColor)
@{Apps=@($Apps);Plan=[bool]$Plan} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'dispatched.json')
exit 0
'@ | Set-Content -LiteralPath (Join-Path $sandbox 'install.ps1')
    & $shell -NoProfile -File (Join-Path $sandbox 'manage.ps1') -Apps 'present,absent,config' -Plan *> $null
    Assert ($LASTEXITCODE -eq 0) 'Public manager dispatch failed'
    $dispatched=Get-Content (Join-Path $sandbox 'dispatched.json') -Raw | ConvertFrom-Json
    Assert ($dispatched.Plan -and ($dispatched.Apps -join ',') -eq 'absent') 'Public entry point sent installed/configuration apps to installer'
    $menu=@('4','','r','q') | & $shell -NoProfile -File (Join-Path $sandbox 'manage.ps1') 6>&1 | Out-String
    Assert ($LASTEXITCODE -eq 0 -and $menu -like '*Instalar todos*' -and $menu -like '*Present*') 'Installed view/refresh/quit menu loop failed'
} finally {
    $target=[IO.Path]::GetFullPath($sandbox)
    Assert ($target.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))) 'Unsafe cleanup'
    Remove-Item -LiteralPath $target -Recurse -Force
}
Write-Host 'PASS: batched inventory, registration/command detection, unknown/configuration states and missing-only selection.'
