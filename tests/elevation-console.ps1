# Manual test: real UAC, no app installations or Windows setting changes.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../modules/installer/elevation.ps1"
try {
    $script:GuepardoAdminSession=Start-GuepardoAdminSession
    $command='$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 }; exit 27'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $code=Invoke-GuepardoAdminCommand (Get-Process -Id $PID).Path $encoded
    if ($code -ne 0) { throw "Worker did not execute with administrator privileges: $code" }
    $bash=Join-Path $env:SystemDrive 'msys64/usr/bin/bash.exe'
    if (Test-Path -LiteralPath $bash) {
        $module=(Resolve-Path "$PSScriptRoot/../modules/installer/msys.ps1").Path
        $bridge=(Resolve-Path "$PSScriptRoot/../scripts/install-dotagents-windows.sh").Path
        $quote={param($value) "'"+$value.Replace("'","''")+"'"}
        $command=". $(& $quote $module); `$env:MSYS='winsymlinks:nativestrict'; `$env:GUEPARDO_DOTAGENTS_USER_HOME=$(& $quote $env:USERPROFILE); exit (Invoke-GuepardoMsysStep -Bash $(& $quote $bash) -Script $(& $quote $bridge) -Mode probe)"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        if ((Invoke-GuepardoAdminCommand (Get-Process -Id $PID).Path $encoded) -ne 0) { throw 'Elevated MSYS symlink probe failed.' }
        Write-Host 'PASS: MSYS created and removed a real native symlink in the original user profile.'
    }
    Write-Host 'PASS: real UAC, non-elevated client and elevated worker communication.'
} finally { Stop-GuepardoAdminSession }
