$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT') { Write-Host 'SKIP: Windows/MSYS argument bridge'; exit 0 }
. (Join-Path $PSScriptRoot '../modules/installer/msys.ps1')
function Assert($condition,$message) { if(-not $condition) { throw $message } }
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('dotagents bridge '+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
$saved=@{}
foreach($name in @('MSYS','GUEPARDO_DOTAGENTS_SOURCE','GUEPARDO_DOTAGENTS_USER_HOME','GUEPARDO_TEST_OUTPUT','GUEPARDO_TEST_INSTALL_CODE','GUEPARDO_TEST_SYNC_CODE')) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $repo=Join-Path $sandbox 'repo (with spaces) and ''quote'' $cash'
    $userHome=Join-Path $sandbox ('profile (with spaces) and ''quote'' '+[char]0x00e7)
    New-Item -ItemType Directory (Join-Path $repo 'bin'),$userHome | Out-Null
    $scriptFile=(Resolve-Path (Join-Path $PSScriptRoot '../scripts/install-dotagents-windows.sh')).Path
    Assert (-not ([IO.File]::ReadAllText($scriptFile).Contains("`r"))) 'Runtime Bash script has CRLF endings'
    $scriptCopy=Join-Path $sandbox 'bridge script (with spaces) and ''quote''.sh'
    Copy-Item -LiteralPath $scriptFile -Destination $scriptCopy
    $scriptFile=$scriptCopy
    $installBody=@'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$PWD" == "$(cygpath -u -- "$GUEPARDO_DOTAGENTS_SOURCE")" ]] || exit 41
[[ "$HOME" == "$(cygpath -u -- "$GUEPARDO_DOTAGENTS_USER_HOME")" ]] || exit 42
printf 'install\n' >> "$(cygpath -u -- "$GUEPARDO_TEST_OUTPUT")"
exit "${GUEPARDO_TEST_INSTALL_CODE:-0}"
'@
    $syncBody=@'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sync\n' >> "$(cygpath -u -- "$GUEPARDO_TEST_OUTPUT")"
exit "${GUEPARDO_TEST_SYNC_CODE:-0}"
'@
    $utf8=[Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $repo 'install.sh'),$installBody.Replace("`r`n","`n")+"`n",$utf8)
    [IO.File]::WriteAllText((Join-Path $repo 'bin/sync'),$syncBody.Replace("`r`n","`n")+"`n",$utf8)
    $env:GUEPARDO_DOTAGENTS_SOURCE=$repo; $env:GUEPARDO_DOTAGENTS_USER_HOME=$userHome
    $env:GUEPARDO_TEST_OUTPUT=Join-Path $sandbox 'stages.txt'; $env:MSYS='winsymlinks:nativestrict'
    $bashCandidates=@((Join-Path $env:SystemDrive 'msys64/usr/bin/bash.exe'),(Join-Path $env:ProgramFiles 'Git/bin/bash.exe'))
    $tested=0
    foreach($bash in $bashCandidates | Select-Object -Unique) {
        if(-not (Test-Path -LiteralPath $bash)) { continue }
        $tested++
        $probeCode=Invoke-GuepardoMsysStep -Bash $bash -Script $scriptFile -Mode probe
        Assert ($probeCode -in @(0,77)) "Unexpected native symlink probe result: $probeCode"
        Assert (@(Get-ChildItem -LiteralPath $userHome -Filter '.guepardo-symlink-*' -Force).Count -eq 0) 'Symlink probe left temporary files'
        $env:GUEPARDO_TEST_INSTALL_CODE='0'; $env:GUEPARDO_TEST_SYNC_CODE='0'
        Set-Content $env:GUEPARDO_TEST_OUTPUT ''
        $code=Invoke-GuepardoMsysStep -Bash $bash -Script $scriptFile -Mode install
        $stages=@(Get-Content $env:GUEPARDO_TEST_OUTPUT | Where-Object { $_ })
        Assert ($code -eq 0 -and ($stages -join ',') -eq 'install,sync') "Native Bash path/quote handling failed: $bash"
        Set-Content $env:GUEPARDO_TEST_OUTPUT ''
        $env:GUEPARDO_TEST_INSTALL_CODE='17'
        $code=Invoke-GuepardoMsysStep -Bash $bash -Script $scriptFile -Mode install
        $stages=@(Get-Content $env:GUEPARDO_TEST_OUTPUT | Where-Object { $_ })
        Assert ($code -eq 17 -and ($stages -join ',') -eq 'install') 'Sync ran after install failed, or its exit code was lost'
        $env:GUEPARDO_TEST_INSTALL_CODE='0'; $env:GUEPARDO_TEST_SYNC_CODE='23'
        $code=Invoke-GuepardoMsysStep -Bash $bash -Script $scriptFile -Mode install
        Assert ($code -eq 23) 'Sync exit code was lost'
    }
    Assert ($tested -gt 0) 'No native Bash was available for regression tests'
    # Exercise orchestration without package installs or writes to the real user profile.
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../install.ps1'),[ref]$null,[ref]$null)
    $definition=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-Dotagents'},$true)
    $script:installerRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Invoke-Expression ($definition.Extent.Text.Replace('$PSScriptRoot','$script:installerRoot'))
    function Get-GuepardoCheckout { param($Repository,$Name) return $repo }
    function Install-RequiredWingetPackage { param($Id) }
    function New-Item { param($ItemType,$Path,[switch]$Force) }
    function Test-Path { param($Path) return $true }
    function Invoke-GuepardoMsysStep {
        param($Bash,$Script,$Mode,$LogFile)
        $script:stages+=$Mode
        Assert ($env:GUEPARDO_DOTAGENTS_SOURCE -eq $repo -and $env:GUEPARDO_DOTAGENTS_USER_HOME -eq $env:USERPROFILE) 'Wrong upstream environment'
        if($Mode -eq $script:failingStage) { return 17 }; return 0
    }
    foreach($stage in @('runtime','dependencies','probe','install')) {
        $script:failingStage=$stage; $script:stages=@()
        $beforeMsys=$env:MSYS; $beforeSource=$env:GUEPARDO_DOTAGENTS_SOURCE; $beforeHome=$env:GUEPARDO_DOTAGENTS_USER_HOME
        $failure=$null
        try { Install-Dotagents } catch { $failure=$_ }
        Assert ($failure -and $failure.Exception.Message -like '*exit 17*' -and $failure.Exception.Message -notlike '*Developer Mode*') "Unrelated failure was mislabeled: $($failure.Exception.Message)"
        Assert ($env:MSYS -eq $beforeMsys -and $env:GUEPARDO_DOTAGENTS_SOURCE -eq $beforeSource -and $env:GUEPARDO_DOTAGENTS_USER_HOME -eq $beforeHome) 'Bridge environment was not restored'
        $expected=if($stage -eq 'runtime'){1}elseif($stage -eq 'dependencies'){2}elseif($stage -eq 'probe'){3}else{4}
        Assert ($script:stages.Count -eq $expected) 'Orchestrator continued after a failed MSYS phase'
    }
    function Invoke-GuepardoMsysStep {
        param($Bash,$Script,$Mode,$LogFile)
        if($Mode -eq 'probe') { return 77 }; return 0
    }
    $script:elevatedCalls=0
    function Write-Log { param($Message,$Level) }
    function Invoke-GuepardoElevatedDotagents {
        param($Bash,$Script,$Source,$UserHome,$LogFile)
        Assert ($Source -eq $repo -and $UserHome -eq $env:USERPROFILE) 'Elevation lost original user/source'
        $script:elevatedCalls++; return $script:elevatedCode
    }
    $script:elevatedCode=0
    Install-Dotagents
    Assert ($script:elevatedCalls -eq 1) 'Symlink denial did not trigger scoped elevation'
    $script:elevatedCode=19;$failure=$null
    try { Install-Dotagents } catch { $failure=$_ }
    Assert ($failure -and $failure.Exception.Message -like '*exit 19*') 'Elevated sync failure swallowed'
    Write-Host "PASS: $tested native Bash implementations; literal paths, install/sync ordering, failures and environment restoration."
} finally {
    foreach($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $sandbox -Recurse -Force
}
exit 0
