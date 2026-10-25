function Invoke-GuepardoMsysStep {
    param(
        [Parameter(Mandatory)][string]$Bash,
        [Parameter(Mandatory)][string]$Script,
        [ValidateSet('runtime','dependencies','install')][string]$Mode,
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
