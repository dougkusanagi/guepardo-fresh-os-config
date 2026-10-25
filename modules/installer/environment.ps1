function Merge-GuepardoPath {
    param([string[]]$Paths)
    $seen=@{}; $result=New-Object System.Collections.Generic.List[string]
    foreach($pathList in $Paths) {
        foreach($entry in ([string]$pathList).Split(';')) {
            $entry=$entry.Trim().Trim('"')
            if($entry -and -not $seen.ContainsKey($entry.TrimEnd('\'))) {
                $seen[$entry.TrimEnd('\')]=$true; $result.Add($entry)
            }
        }
    }
    return $result -join ';'
}

function Sync-GuepardoProcessEnvironment {
    param(
        [string]$UserPath = [Environment]::GetEnvironmentVariable('Path','User'),
        [string]$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    )
    # Refresh tool roots selectively. Never import machine TEMP/TMP/HOME over user state.
    foreach($name in @('NVM_HOME','NVM_SYMLINK','CARGO_HOME','RUSTUP_HOME','COMPOSER_HOME')) {
        if(-not [Environment]::GetEnvironmentVariable($name,'Process')) {
            $value=[Environment]::GetEnvironmentVariable($name,'User')
            if(-not $value) { $value=[Environment]::GetEnvironmentVariable($name,'Machine') }
            if($value) { [Environment]::SetEnvironmentVariable($name,$value,'Process') }
        }
    }
    $known=@()
    if($env:USERPROFILE) {
        foreach($suffix in @('scoop/shims','.cargo/bin','.bun/bin','.local/bin','.vite-plus/bin')) { $known+=Join-Path $env:USERPROFILE $suffix }
    }
    if($env:SCOOP) { $known+=Join-Path $env:SCOOP 'shims' }
    if($env:LOCALAPPDATA) { $known+=Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links' }
    $known=@($known | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
    $env:Path=Merge-GuepardoPath -Paths (@($env:Path,$UserPath,$MachinePath)+$known)
}

function Get-GuepardoCommand {
    param([string]$Name)
    foreach($candidate in @($Name,"$Name.exe","$Name.cmd","$Name.bat","$Name.ps1")) {
        $command=Get-Command $candidate -ErrorAction SilentlyContinue
        if($command) { return $command }
    }
    return $null
}

function New-GuepardoTempDirectory {
    param([Parameter(Mandatory)][string]$Root)
    $directory=Join-Path ([IO.Path]::GetFullPath($Root)) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $probe=Join-Path $directory '.write-probe'
    [IO.File]::WriteAllText($probe,'ok'); [IO.File]::Delete($probe)
    return $directory
}

function Remove-GuepardoTemporaryPath {
    param([string]$Path,[string]$Root)
    if(-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $true }
    $target=[IO.Path]::GetFullPath($Path)
    $allowed=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $target.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw "Refusing cleanup outside the owned temporary directory: $Path" }
    try { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop; return $true }
    catch { Write-Warning "Temporary files remain locked; installation results are preserved. Clean up later: $target"; return $false }
}
