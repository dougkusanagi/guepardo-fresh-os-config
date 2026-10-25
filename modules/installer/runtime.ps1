# Compatible with the inbox Windows PowerShell 5.1 bootstrap host.
function Get-GuepardoPowerShellAsset {
    param($Release,[string]$Architecture)
    if ($Release.prerelease -or $Release.draft -or $Release.tag_name -notmatch '^v(7\.\d+\.\d+)$') { throw 'Invalid stable PowerShell release.' }
    $version=$Matches[1]
    if ($Architecture -notin @('x64','arm64','x86')) { throw "Unsupported Windows architecture: $Architecture" }
    $name="PowerShell-$version-win-$Architecture.zip"
    $asset=@($Release.assets | Where-Object name -eq $name) | Select-Object -First 1
    if (-not $asset -or $asset.browser_download_url -notlike 'https://github.com/PowerShell/PowerShell/releases/download/*') { throw "Official PowerShell asset missing: $name" }
    return @{Version=$version;Name=$name;Asset=$asset}
}

function Get-GuepardoRuntimeChecksum {
    param([string]$Text,[string]$Name)
    foreach ($line in ($Text -split '\r?\n')) {
        $line=$line.Trim().TrimStart([char]0xFEFF)
        if ($line -match ('^([a-fA-F0-9]{64})\s+\*?' + [regex]::Escape($Name) + '$')) { return $Matches[1] }
    }
    throw "SHA256 missing for $Name"
}

function Install-GuepardoPowerShellRuntime {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $release=Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -Headers @{'User-Agent'='Guepardo-Installer'} -TimeoutSec 30
    $arch=if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $arch=switch ($arch) { 'AMD64' {'x64'}; 'ARM64' {'arm64'}; 'x86' {'x86'}; default { throw "Unsupported Windows architecture: $arch" } }
    $info=Get-GuepardoPowerShellAsset $release $arch
    $root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Guepardo/Runtime/PowerShell'
    $destination=Join-Path $root "$($info.Version)-$arch"
    $exe=Join-Path $destination 'pwsh.exe'
    if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath (Join-Path $destination '.verified'))) { return $exe }
    $existing=Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($existing) {
        $version=& $existing.Source -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
        if ($LASTEXITCODE -eq 0 -and ([string]$version).Trim() -eq $info.Version) { return $existing.Source }
    }
    Write-Host "  Preparando PowerShell $($info.Version) ($arch)..." -ForegroundColor Cyan
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-runtime-'+[guid]::NewGuid())
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $hashAsset=$release.assets | Where-Object name -eq 'hashes.sha256' | Select-Object -First 1
        if (-not $hashAsset -or $hashAsset.browser_download_url -notlike 'https://github.com/PowerShell/PowerShell/releases/download/*') { throw 'Official PowerShell checksums missing.' }
        # Release manifests may be UTF-16LE with BOM; HTTP Content decoding differs
        # between Windows PowerShell and pwsh. Read the original bytes with BOM detection.
        $manifest=Join-Path $temp 'hashes.sha256'
        Invoke-WebRequest -UseBasicParsing $hashAsset.browser_download_url -OutFile $manifest -TimeoutSec 60
        $hashText=[IO.File]::ReadAllText($manifest)
        $expected=Get-GuepardoRuntimeChecksum $hashText $info.Name
        $zip=Join-Path $temp 'runtime.zip'
        $savedProgress=$ProgressPreference
        try { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing $info.Asset.browser_download_url -OutFile $zip -TimeoutSec 600 }
        finally { $ProgressPreference=$savedProgress }
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expected) { throw 'PowerShell download failed SHA256 verification.' }
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $destination -Force
        if (-not (Test-Path -LiteralPath $exe)) { throw 'PowerShell extraction is incomplete.' }
        Set-Content -LiteralPath (Join-Path $destination '.verified') -Value $expected
        return $exe
    } finally {
        # Only remove the GUID directory created by this invocation.
        $resolved=[IO.Path]::GetFullPath($temp)
        $allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        if ($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}

function Invoke-GuepardoPowerShellRuntime {
    param([string]$Installer,[System.Collections.IDictionary]$Parameters)
    $exe=Install-GuepardoPowerShellRuntime
    $payload=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-arguments-'+[guid]::NewGuid()+'.clixml')
    $oldMarker=$env:GUEPARDO_RUNTIME_HOST
    try {
        $copy=@{}
        foreach ($key in $Parameters.Keys) { $value=$Parameters[$key]; if ($value -is [Management.Automation.SwitchParameter]) { $value=[bool]$value }; $copy[$key]=$value }
        @{Installer=$Installer;Parameters=$copy} | Export-Clixml -LiteralPath $payload
        $command='$data=Import-Clixml -LiteralPath '''+$payload.Replace("'","''")+'''; $bound=$data.Parameters; & $data.Installer @bound; exit $LASTEXITCODE'
        $env:GUEPARDO_RUNTIME_HOST=$exe
        # Calling a native shell through this function's success stream makes PowerShell
        # redirect its stdout. The picker then loses its console and its menu is captured
        # as part of the return value. Inherit the console handles directly instead.
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $process=Start-Process -FilePath $exe -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $encoded" -NoNewWindow -Wait -PassThru
        return $process.ExitCode
    } finally { $env:GUEPARDO_RUNTIME_HOST=$oldMarker; Remove-Item -LiteralPath $payload -Force -ErrorAction SilentlyContinue }
}
