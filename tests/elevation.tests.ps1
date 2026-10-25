$ErrorActionPreference='Stop'
. "$PSScriptRoot/../modules/installer/elevation.ps1"
function Assert($ok,$message) { if(-not $ok){throw $message} }
$script:starts=0
# Launch the real worker without elevation, exercising IPC without a UAC prompt.
function Start-Process {
    param($FilePath,$Verb,$WindowStyle,[switch]$PassThru,$ArgumentList)
    Assert ($Verb -eq 'RunAs' -and $WindowStyle -eq 'Hidden') 'UAC/background launch missing'
    $script:starts++
    Microsoft.PowerShell.Management\Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle Hidden -PassThru
}
$script:GuepardoAdminSession=$null
try {
    $script:GuepardoAdminSession=Start-GuepardoAdminSession
    $process=$script:GuepardoAdminSession.Process
    $exe=(Get-Process -Id $PID).Path
    foreach($expected in @(17,0)) {
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("exit $expected"))
        Assert ((Invoke-GuepardoAdminCommand $exe $encoded) -eq $expected) 'Worker lost child exit code'
    }
    Assert ($script:starts -eq 1) 'Worker restarted between commands'
    $rejected=$false
    try { Invoke-GuepardoAdminCommand 'cmd.exe' 'AAAA' } catch { $rejected=$true }
    Assert $rejected 'Worker accepted an arbitrary executable'
    Stop-GuepardoAdminSession
    Assert ($null -eq $script:GuepardoAdminSession) 'Admin session not cleared'
    Assert ($process.WaitForExit(10000)) 'Worker did not terminate after stop'
    function Start-Process { throw 'Simulated UAC cancellation' }
    $cancelled=$false
    try { Start-GuepardoAdminSession } catch { $cancelled=$_.Exception.Message -like '*Nenhum aplicativo foi instalado*' }
    Assert $cancelled 'UAC cancellation was not reported clearly'
} finally { Stop-GuepardoAdminSession }
Write-Host 'PASS: real worker IPC, one session for multiple commands, exit codes, request validation, shutdown and UAC cancellation.'
