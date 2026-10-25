$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../modules/installer/environment.ps1')
. (Join-Path $PSScriptRoot '../modules/installer/releases.ps1')
function Assert($condition,$message) { if(-not $condition) { throw $message } }
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-env-'+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
$oldPath=$env:Path; $oldTemp=$env:TEMP; $oldTmp=$env:TMP
$homeBefore=$env:HOME; $profileBefore=$env:USERPROFILE
try {
    $session=Join-Path $sandbox 'session-bin'; New-Item -ItemType Directory $session | Out-Null
    $env:Path=$session; $env:TEMP=Join-Path $sandbox 'user-temp'; $env:TMP=Join-Path $sandbox 'user-tmp'
    Sync-GuepardoProcessEnvironment -UserPath 'C:\user-bin;C:\shared' -MachinePath 'C:\machine-bin;c:\SHARED'
    Assert ($env:TEMP -eq (Join-Path $sandbox 'user-temp') -and $env:TMP -eq (Join-Path $sandbox 'user-tmp')) 'Refresh replaced user TEMP/TMP'
    Assert ($env:HOME -eq $homeBefore -and $env:USERPROFILE -eq $profileBefore) 'Refresh replaced identity variables'
    Assert ($env:Path.Split(';')[0] -eq $session -and 'C:\user-bin' -in $env:Path.Split(';') -and 'C:\machine-bin' -in $env:Path.Split(';')) 'Session paths were lost'
    Assert (@($env:Path.Split(';')|Where-Object {$_ -ieq 'C:\shared'}).Count -eq 1) 'PATH contains duplicate entries'
    $tempRoot=Join-Path $sandbox 'owned'; $temp=New-GuepardoTempDirectory $tempRoot
    Assert ($temp.StartsWith($tempRoot) -and (Test-Path $temp)) 'Owned writable temp was not created'
    $outside=Join-Path $sandbox 'outside'; Set-Content $outside 'preserve'
    $refused=$false; try { Remove-GuepardoTemporaryPath $outside $tempRoot } catch { $refused=$true }
    Assert ($refused -and (Test-Path $outside)) 'Cleanup escaped the owned directory'
    function Remove-Item { throw [UnauthorizedAccessException]::new('Simulated locked Composer files') }
    $oldWarning=$WarningPreference
    try { $WarningPreference='SilentlyContinue'; $removed=Remove-GuepardoTemporaryPath $temp $tempRoot }
    finally { $WarningPreference=$oldWarning; Microsoft.PowerShell.Management\Remove-Item Function:\Remove-Item }
    Assert (-not $removed -and (Test-Path $temp)) 'Locked cleanup aborted or removed files incorrectly'
    Assert (Remove-GuepardoTemporaryPath $temp $tempRoot) 'Unlocked cleanup failed'
    function Get-Command { param($Name,$ErrorAction) if($Name -eq 'codex.exe') { return @{Name='codex.exe';Source='fake-codex.exe'} }; return $null }
    Assert ((Get-GuepardoCommand 'codex').Name -eq 'codex.exe') 'Executable suffix detection failed'
    $script:apiCalls=0
    function Invoke-RestMethod {
        $script:apiCalls++
        $exception=[Exception]::new('No published release')
        $exception | Add-Member -MemberType NoteProperty -Name Response -Value @{StatusCode=404}
        throw $exception
    }
    $missing=Get-GuepardoRelease 'example/no-release' -AllowMissing
    $missing=Get-GuepardoRelease 'example/no-release' -AllowMissing
    Assert ($null -eq $missing -and $script:apiCalls -eq 1) 'Expected 404 was not cached as a missing release'
    $denied=$false; try { Get-GuepardoRelease 'example/must-have-release' } catch { $denied=$true }
    Assert $denied 'Required release lookup swallowed 404'
    Write-Host 'PASS: session environment preservation, writable temp, locked cleanup, executable suffixes and optional releases.'
} finally {
    $env:Path=$oldPath; $env:TEMP=$oldTemp; $env:TMP=$oldTmp
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $sandbox -Recurse -Force
}
exit 0
