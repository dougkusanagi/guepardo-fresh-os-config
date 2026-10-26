function Import-GuepardoMsvcEnvironment {
    param([Parameter(Mandatory)][string]$DevCmd,[ValidateRange(1,300)][int]$TimeoutSeconds=120)
    if(-not(Test-Path -LiteralPath $DevCmd -PathType Leaf)){throw "VsDevCmd.bat não encontrado: $DevCmd"}
    $root=[IO.Path]::GetTempPath()
    $directory=Join-Path $root ('guepardo-msvc-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $process=$null
    try {
        # No user path is embedded in a cmd /c command string. The batch filename
        # is constant, its working directory is separate, and VS is passed via env.
        [IO.File]::WriteAllText((Join-Path $directory 'environment.cmd'), "@echo off`r`ncall `"%GUEPARDO_VSDEVCMD%`" -arch=x64 -host_arch=x64 >nul`r`nif errorlevel 1 exit /b %errorlevel%`r`nset`r`n",[Text.Encoding]::ASCII)
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=Join-Path $env:WINDIR 'System32/cmd.exe'
        $info.Arguments='/d /u /v:off /c environment.cmd'
        $info.WorkingDirectory=$directory
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.StandardOutputEncoding=[Text.Encoding]::Unicode
        $info.StandardErrorEncoding=[Text.Encoding]::Unicode
        $info.EnvironmentVariables.Remove('VCToolsInstallDir')
        $info.EnvironmentVariables['GUEPARDO_VSDEVCMD']=$DevCmd
        $process=[Diagnostics.Process]::new();$process.StartInfo=$info
        [void]$process.Start()
        $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){ $process.Kill();throw 'A preparação do MSVC excedeu o tempo limite.' }
        if($process.ExitCode -ne 0){throw "Não foi possível preparar o MSVC (exit $($process.ExitCode)): $($errors.Result)"}
        $variables=@{}
        foreach($line in ($output.Result -split '\r?\n')){if($line -match '^([^=]+)=(.*)$'){$variables[$Matches[1]]=$Matches[2]}}
        if(-not $variables['VCToolsInstallDir']){throw 'O Visual Studio não disponibilizou as ferramentas C++ após VsDevCmd.'}
        foreach($key in $variables.Keys){
            if($key -notin @('TEMP','TMP','GUEPARDO_VSDEVCMD')){[Environment]::SetEnvironmentVariable($key,$variables[$key],'Process')}
        }
    } finally {
        if($process){$process.Dispose()}
        $target=[IO.Path]::GetFullPath($directory)
        $allowed=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
        if($target.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $target -Recurse -Force}
    }
}
