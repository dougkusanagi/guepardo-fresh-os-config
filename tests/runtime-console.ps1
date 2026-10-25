# Interactive smoke test. Select T and Enter; never installs apps or downloads a runtime.
param([switch]$Child)
$ErrorActionPreference='Stop'
if ($Child) {
    . "$PSScriptRoot/../modules/installer/ui.ps1"
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw 'Runtime lost the interactive console.' }
    $catalog=[pscustomobject]@{profiles=@([pscustomobject]@{id='cli';label='Terminal';platforms=@('windows')});apps=@([pscustomobject]@{id='demo';name='App de teste (nenhuma instalacao)';profiles=@('cli')})}
    $chosen=@(Select-GuepardoApps $catalog)
    if (($chosen -join ',') -ne 'demo') { throw 'Selection failed' }
    Write-Host 'PASS: inherited console, visible menu and real keyboard selection.'
    exit 0
}
. "$PSScriptRoot/../modules/installer/runtime.ps1"
function Install-GuepardoPowerShellRuntime { (Get-Command pwsh.exe -ErrorAction Stop).Source }
exit (Invoke-GuepardoPowerShellRuntime $PSCommandPath @{Child=$true})
