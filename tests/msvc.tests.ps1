$ErrorActionPreference='Stop'
. "$PSScriptRoot/../modules/installer/msvc.ps1"
function Assert($ok,$message){if(-not $ok){throw $message}}
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('MSVC with spaces & quote '' '+[char]0x00e7+' '+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
$saved=@{};foreach($name in @('VCToolsInstallDir','GUEPARDO_MSVC_TEST','TEMP','TMP','Path')){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
    $batch=Join-Path $sandbox 'Vs Dev Cmd.bat'
    [IO.File]::WriteAllText($batch,"@echo off`r`nset `"VCToolsInstallDir=C:\fake tools\`"`r`nset `"GUEPARDO_MSVC_TEST=value=with spaces`"`r`nset TEMP=C:\should-not-replace-temp`r`nexit /b 0`r`n",[Text.Encoding]::ASCII)
    Import-GuepardoMsvcEnvironment $batch
    Assert ($env:VCToolsInstallDir -eq 'C:\fake tools\' -and $env:GUEPARDO_MSVC_TEST -eq 'value=with spaces') 'Batch path or environment parsing failed'
    Assert ($env:TEMP -eq $saved['TEMP'] -and $env:TMP -eq $saved['TMP']) 'MSVC replaced session TEMP/TMP'
    [IO.File]::WriteAllText($batch,"@echo off`r`nexit /b 19`r`n",[Text.Encoding]::ASCII)
    $failed=$false;try{Import-GuepardoMsvcEnvironment $batch}catch{$failed=$_.Exception.Message -like '*exit 19*'}
    Assert $failed 'VsDevCmd failure swallowed'
    [IO.File]::WriteAllText($batch,"@echo off`r`nexit /b 0`r`n",[Text.Encoding]::ASCII)
    $failed=$false;try{Import-GuepardoMsvcEnvironment $batch}catch{$failed=$true};Assert $failed 'Empty developer environment accepted'
} finally {
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    $target=[IO.Path]::GetFullPath($sandbox)
    Assert ($target.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))) 'Unsafe cleanup'
    Remove-Item -LiteralPath $target -Recurse -Force
}
Write-Host 'PASS: real cmd.exe, spaced/quoted paths, environment values, failure propagation and TEMP/TMP preservation.'
