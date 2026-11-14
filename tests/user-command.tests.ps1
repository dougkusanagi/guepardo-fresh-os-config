$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../modules/installer/environment.ps1')
function Assert($condition,$message) { if(-not $condition) { throw $message } }
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-user-command-'+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
$oldPath=$env:Path
try {
    $target=Join-Path $sandbox 'repo with spaces\tool.cmd'
    New-Item -ItemType Directory (Split-Path $target) | Out-Null
    Set-Content -LiteralPath $target -Value "@echo off`r`necho tool:%*" -Encoding ASCII
    $bin=Join-Path $sandbox 'bin'
    $script:userPath='C:\existing'; $script:writes=0
    $get={ $script:userPath }; $set={ param($v) $script:userPath=$v; $script:writes++ }

    $shim=Install-GuepardoUserCommand -Name 'tool' -Target $target -BinDirectory $bin -GetUserPath $get -SetUserPath $set
    Assert (Test-Path $shim) 'Shim was not created'
    Assert ($script:userPath -eq "C:\existing;$bin") "User PATH not updated: $script:userPath"
    Assert ($env:Path.Split(';') -contains $bin) 'Current session PATH not updated'
    $output=& cmd.exe /d /c "`"$shim`" a b"
    Assert ($output -eq 'tool:a b') "Shim did not forward arguments: $output"

    # Running again rewrites the shim but never duplicates the PATH entry.
    Install-GuepardoUserCommand -Name 'tool' -Target $target -BinDirectory "$bin\" -GetUserPath $get -SetUserPath $set | Out-Null
    Assert ($script:writes -eq 1) 'PATH was written twice'

    $rejected=$false; try { Install-GuepardoUserCommand -Name 'bad name&' -Target $target -BinDirectory $bin -GetUserPath $get -SetUserPath $set } catch { $rejected=$true }
    Assert $rejected 'Unsafe command name accepted'
    $missing=$false; try { Install-GuepardoUserCommand -Name 'x' -Target (Join-Path $sandbox 'none.cmd') -BinDirectory $bin -GetUserPath $get -SetUserPath $set } catch { $missing=$true }
    Assert $missing 'Missing target accepted'
    Write-Host 'User command tests passed.'
} finally {
    $env:Path=$oldPath
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
