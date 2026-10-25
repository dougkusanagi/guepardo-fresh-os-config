function Invoke-GuepardoMsysStep {
    param(
        [Parameter(Mandatory)][string]$Bash,
        [Parameter(Mandatory)][string]$Script,
        [ValidateSet('runtime','dependencies','probe','install')][string]$Mode,
        [string]$LogFile
    )
    $scriptFile=(Resolve-Path -LiteralPath $Script -ErrorAction Stop).Path.Replace('\','/')
    $savedPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        # No -c string: Windows receives only ordinary argv values, with no nested shell quotes.
        & $Bash --noprofile --norc $scriptFile $Mode 2>&1 | ForEach-Object {
            $line=$_.ToString()
            Write-Host $line
            if($LogFile) { Add-Content -LiteralPath $LogFile -Value $line }
        }
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$savedPreference }
    return [int]$code
}

function Invoke-GuepardoElevatedDotagents {
    param([string]$Bash,[string]$Script,[string]$Source,[string]$UserHome,[string]$LogFile)
    # Carry the original user's paths explicitly across UAC, never use the elevated HOME.
    $values=@($Bash,$Script,$Source,$UserHome,$LogFile,(Join-Path $PSScriptRoot 'msys.ps1'))
    $quoted=@($values | ForEach-Object { "'"+([string]$_).Replace("'","''")+"'" })
    $command="`$ErrorActionPreference='Stop'; . $($quoted[5]); `$env:MSYS='winsymlinks:nativestrict'; `$env:GUEPARDO_DOTAGENTS_SOURCE=$($quoted[2]); `$env:GUEPARDO_DOTAGENTS_USER_HOME=$($quoted[3]); exit (Invoke-GuepardoMsysStep -Bash $($quoted[0]) -Script $($quoted[1]) -Mode install -LogFile $($quoted[4]))"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    if ($script:GuepardoAdminSession) { return Invoke-GuepardoAdminCommand -Executable (Get-Process -Id $PID).Path -EncodedCommand $encoded }
    try {
        $process=Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    } catch { throw "Não foi possível autorizar a instalação do dotagents via UAC: $_" }
    return $process.ExitCode
}
