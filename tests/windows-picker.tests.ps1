$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules/windows-picker.ps1')
$selected=@{}
Switch-WindowsPickerItem -Selected $selected -Id jellyfin
if(-not $selected.jellyfin -or $selected.cli){throw 'Jellyfin must be independent'}
Switch-WindowsPickerItem -Selected $selected -Id all
if(@($selected.Values | Where-Object {$_}).Count -ne 6){throw 'Todos must select all six modules'}
Switch-WindowsPickerItem -Selected $selected -Id all
if(@($selected.Values | Where-Object {$_}).Count){throw 'Todos must deselect all modules'}
Switch-WindowsPickerItem -Selected $selected -Id jellyfin
$output=Show-WindowsPicker -Selected $selected -Focus 5 6>&1 | Out-String
if($output -notlike '*Jellyfin completo*' -or $output -notlike '*Media Bar*' -or $output -notlike '*1 modulos selecionados*'){throw 'Picker must describe selected Jellyfin module'}
function Clear-Host {}
function Show-WindowsPicker {}
$script:keys=[Collections.Queue]::new()
function Read-WindowsPickerKey {if(-not $script:keys.Count){throw 'Unexpected extra key read'}; return $script:keys.Dequeue()}
# Enter vazio nao deve instalar; numero 6 escolhe Jellyfin e Enter confirma.
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=13;Character=[char]13})
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=54;Character='6'})
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=13;Character=[char]13})
if((Select-WindowsProfiles) -ne 'jellyfin'){throw 'Keyboard selection must choose Jellyfin only'}
# Setas navegam, Espaco marca CLI e numero 6 adiciona Jellyfin.
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=40;Character=[char]0})
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=38;Character=[char]0})
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=32;Character=' '})
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=54;Character='6'})
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=13;Character=[char]13})
if((Select-WindowsProfiles) -ne 'cli,jellyfin'){throw 'Keyboard must support multiple modules'}
$script:keys.Enqueue([pscustomobject]@{VirtualKeyCode=81;Character='q'})
if($null -ne (Select-WindowsProfiles)){throw 'Q must cancel'}
Write-Host 'PASS: Windows picker groups, independent selection, Todos and rendering.'
