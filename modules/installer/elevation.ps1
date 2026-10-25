function Start-GuepardoAdminSession {
    $name='guepardo-'+[guid]::NewGuid().ToString('N')
    $worker=Join-Path $PSScriptRoot 'admin-worker.ps1'
    $logDirectory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Guepardo/Logs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $startupLog=Join-Path $logDirectory "$name-admin.log"
    $ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $command="try { & '"+$worker.Replace("'","''")+"' -PipeName '$name' -OwnerPid $PID -OwnerSid '$ownerSid' } catch { `$_ | Out-String | Set-Content -LiteralPath '"+$startupLog.Replace("'","''")+"'; exit 1 }"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $pipe=$null;$process=$null
    try {
        Write-Host '  Autorize o UAC uma vez para as etapas administrativas.' -ForegroundColor Cyan
        $process=Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -WindowStyle Hidden -PassThru -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
        $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', $name, [IO.Pipes.PipeDirection]::InOut)
        $waiting=[Diagnostics.Stopwatch]::StartNew()
        while (-not $pipe.IsConnected) {
            try { $pipe.Connect(500) } catch [TimeoutException] {
                if ($process.HasExited) { throw 'O auxiliar administrativo encerrou durante a inicialização.' }
                if ($waiting.Elapsed.TotalSeconds -ge 30) { throw 'Tempo esgotado ao conectar ao auxiliar administrativo.' }
            }
        }
        $reader=[IO.StreamReader]::new($pipe)
        $writer=[IO.StreamWriter]::new($pipe);$writer.AutoFlush=$true
        if ($reader.ReadLine() -ne 'ready') { throw 'Invalid administrator handshake.' }
        return @{Pipe=$pipe;Reader=$reader;Writer=$writer;Process=$process}
    } catch {
        if ($pipe) { $pipe.Dispose() }
        $detail=if(Test-Path -LiteralPath $startupLog) { Get-Content -LiteralPath $startupLog -Raw } else { $_.Exception.Message }
        Write-Host "  Falha administrativa: $detail" -ForegroundColor Red
        throw "Autorização administrativa não foi concluída. Nenhum aplicativo foi instalado. Diagnóstico: $startupLog. $detail"
    }
}

function Invoke-GuepardoAdminCommand {
    param([string]$Executable,[string]$EncodedCommand)
    if (-not $script:GuepardoAdminSession) { throw 'Administrator session is unavailable; restart the installer.' }
    $session=$script:GuepardoAdminSession
    $session.Writer.WriteLine((@{Action='run';Executable=$Executable;EncodedCommand=$EncodedCommand} | ConvertTo-Json -Compress))
    $line=$session.Reader.ReadLine()
    if (-not $line) { throw 'Administrator session ended unexpectedly.' }
    $result=$line | ConvertFrom-Json
    if ($result.Error) { throw $result.Error }
    return [int]$result.ExitCode
}

function Stop-GuepardoAdminSession {
    if ($script:GuepardoAdminSession) {
        $session=$script:GuepardoAdminSession
        try { $session.Writer.WriteLine('{"Action":"stop"}') } catch {}
        finally { $session.Pipe.Dispose();$script:GuepardoAdminSession=$null }
    }
}
