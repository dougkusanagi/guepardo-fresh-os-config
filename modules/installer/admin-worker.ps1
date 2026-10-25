param([Parameter(Mandatory)][string]$PipeName,[Parameter(Mandatory)][int]$OwnerPid,[Parameter(Mandatory)][string]$OwnerSid)
$ErrorActionPreference='Stop'
# Restrict both the user and the exact connecting installer process.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class GuepardoPipeClient {
 [DllImport("kernel32.dll", SetLastError=true)]
 public static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint processId);
}
'@
if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $OwnerSid) { throw 'Use a autorização UAC da mesma conta Windows que iniciou o instalador.' }
# CurrentUserOnly also checks token ownership across elevation and can reject the
# original non-elevated client. Use an explicit user SID ACL, then verify its PID.
$security=[IO.Pipes.PipeSecurity]::new()
$security.SetAccessRuleProtection($true,$false)
$identity=[Security.Principal.SecurityIdentifier]::new($OwnerSid)
$security.AddAccessRule([IO.Pipes.PipeAccessRule]::new($identity,[IO.Pipes.PipeAccessRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow))
$pipe=[IO.Pipes.NamedPipeServerStreamAcl]::Create($PipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,0,0,$security)
try {
    $pending=$pipe.WaitForConnectionAsync()
    $waiting=[Diagnostics.Stopwatch]::StartNew()
    while (-not $pending.Wait(1000)) { if ($waiting.Elapsed.TotalSeconds -ge 45 -or -not (Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue)) { exit 1 } }
    [uint32]$clientPid=0
    if (-not [GuepardoPipeClient]::GetNamedPipeClientProcessId($pipe.SafePipeHandle.DangerousGetHandle(),[ref]$clientPid) -or $clientPid -ne $OwnerPid) { throw 'Unexpected administrator client.' }
    $reader=[IO.StreamReader]::new($pipe);$writer=[IO.StreamWriter]::new($pipe);$writer.AutoFlush=$true
    $writer.WriteLine('ready')
    $allowed=@((Get-Process -Id $PID).Path,(Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'))
    while ($null -ne ($line=$reader.ReadLine())) {
        $request=$line | ConvertFrom-Json
        if ($request.Action -eq 'stop') { break }
        try {
            if ($request.Action -ne 'run' -or $request.Executable -notin $allowed -or $request.EncodedCommand -notmatch '^[A-Za-z0-9+/=]+$') { throw 'Invalid administrator request.' }
            $process=Start-Process -FilePath $request.Executable -WindowStyle Hidden -Wait -PassThru -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $($request.EncodedCommand)"
            $writer.WriteLine((@{ExitCode=$process.ExitCode} | ConvertTo-Json -Compress))
        } catch { $writer.WriteLine((@{Error=$_.Exception.Message} | ConvertTo-Json -Compress)) }
    }
} finally { $pipe.Dispose() }
