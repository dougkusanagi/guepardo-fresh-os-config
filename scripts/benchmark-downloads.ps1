[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Uri,
    [ValidateRange(65536,16777216)][int]$Bytes = 1048576,
    [ValidateRange(5,120)][int]$TimeoutSeconds = 30
)
$ErrorActionPreference='Stop'
$curl=Get-Command curl.exe -ErrorAction SilentlyContinue
if(-not $curl) { $curl=Get-Command curl -CommandType Application -ErrorAction Stop }
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-benchmark-'+[guid]::NewGuid())
try {
    foreach($address in $Uri) {
        if(([uri]$address).Scheme -ne 'https') { throw 'Only HTTPS download URLs are supported.' }
        $metrics=& $curl.Source --location --silent --show-error --fail --range "0-$($Bytes-1)" --max-filesize $Bytes --max-time $TimeoutSeconds --connect-timeout 10 --output $temporary --write-out '%{http_code}|%{size_download}|%{speed_download}|%{time_total}' $address
        $code=$LASTEXITCODE; $values=([string]$metrics).Split('|')
        [pscustomobject]@{Host=([uri]$address).Host;ExitCode=$code;HttpStatus=$values[0];Bytes=$values[1];BytesPerSecond=$values[2];Seconds=$values[3];RangeSupported=($values[0] -eq '206')}
    }
} finally { if(Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
