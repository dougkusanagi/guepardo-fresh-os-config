#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules/jellyfin.ps1')
function Get-Service { return [pscustomobject]@{Name='JellyfinServer'} }
$output = (Show-JellyfinRestartInstructions -BaseUrl 'http://localhost:8096' 6>&1 | Out-String)
if ($output -notlike "*Restart-Service -Name 'JellyfinServer'*" -or $output -notlike '*administrador*' -or $output -notlike '*Ctrl+Shift+R*') {
    throw 'Aviso local nao inclui comando do servico, elevacao e atualizacao do navegador.'
}
$output = (Show-JellyfinRestartInstructions -BaseUrl 'https://media.example.com' 6>&1 | Out-String)
if ($output -like '*Restart-Service*' -or $output -notlike '*hospeda o servidor*') { throw 'Aviso remoto nao deve reiniciar o servico local.' }
Write-Host 'PASS: aviso de reinicio local e remoto.'
