$ErrorActionPreference='Stop'
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-integration-'+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
$installer=(Resolve-Path (Join-Path $PSScriptRoot '../install.ps1')).Path
$shell=(Get-Process -Id $PID).Path
try {
    $driver=Join-Path $sandbox 'driver.ps1'
    @'
param($Installer,$Sandbox,$Scenario,[switch]$Resume,[switch]$RetryFailed)
$PROFILE=Join-Path $Sandbox 'profile.ps1'
$env:SCOOP=Join-Path $Sandbox 'scoop'
function Get-Command {
    param([string]$Name,$ErrorAction)
    if($Name -eq 'curl.exe') { return @{Name='curl.exe';Source='curl.exe'} }
    if($Name -eq 'scoop') {
        if(Test-Path (Join-Path $Sandbox 'scoop-ready')) { return @{Name='scoop';Source=(Join-Path $env:SCOOP 'shims/scoop.ps1')} }
        return $null
    }
    if($Name -eq 'aria2c' -and (Test-Path (Join-Path $Sandbox 'aria-ready'))) { return @{Name='aria2c';Source='fake-aria2c'} }
    Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue
}
function curl.exe {
    $destination=$args[[array]::IndexOf($args,'--output')+1]
    Set-Content -LiteralPath $destination '# mocked Scoop installer'
    $global:LASTEXITCODE=0
}
function powershell.exe {
    'bootstrap' | Add-Content (Join-Path $Sandbox 'events')
    if($Scenario -eq 'auto-fail') { $global:LASTEXITCODE=1; return }
    Set-Content (Join-Path $Sandbox 'scoop-ready') ready
    $global:LASTEXITCODE=0
}
function scoop {
    $name=([string]$args[1]).Split('/')[-1]
    if($args[0] -eq 'prefix') {
        $prefix=Join-Path $Sandbox "scoop/apps/$name/current"
        if(Test-Path $prefix) { $prefix; $global:LASTEXITCODE=0 } else { $global:LASTEXITCODE=1 }
        return
    }
    ($args -join ' ') | Add-Content (Join-Path $Sandbox 'events')
    if($args[0] -eq 'install') {
        if($name -eq 'aria2') { Set-Content (Join-Path $Sandbox 'aria-ready') ready }
        New-Item -ItemType Directory (Join-Path $Sandbox "scoop/apps/$name/current") -Force | Out-Null
        if($name -eq 'aria2') { Set-Content (Join-Path $Sandbox 'scoop/apps/aria2/current/aria2c.exe') '# fake aria2' }
    }
    $global:LASTEXITCODE=0
}
function winget {
    $id=$args[[array]::IndexOf($args,'--id')+1]
    $marker=Join-Path $Sandbox ($id+'.installed')
    if($args[0] -eq 'list') {
        if(Test-Path $marker) { "$id 1.0"; $global:LASTEXITCODE=0 } else { $global:LASTEXITCODE=1 }
        return
    }
    $id | Add-Content (Join-Path $Sandbox 'installs')
    if($Scenario -eq 'interrupted') { exit 130 }
    if($Scenario -eq 'fail' -or ($Scenario -eq 'dependency' -and $id -eq 'PHP.PHP.8.4')) { $global:LASTEXITCODE=1603; return }
    if($Scenario -ne 'false-success') { Set-Content $marker installed }
    $global:LASTEXITCODE=0
}
$apps=if($Scenario -eq 'dependency') { @('Composer.Composer') } else { @('GitHub.cli') }
if($Scenario -eq 'interrupted') { $apps=@('GitHub.cli','Microsoft.PowerToys') }
if($Scenario -in @('auto','auto-fail')) {
    & $Installer -Apps $apps -NoPrefetch -NoColor -StateDirectory (Join-Path $Sandbox 'state') -CacheDirectory (Join-Path $Sandbox 'cache')
    exit $LASTEXITCODE
}
& $Installer -Apps $apps -Provider winget -NoPrefetch -NoColor -StateDirectory (Join-Path $Sandbox 'state') -CacheDirectory (Join-Path $Sandbox 'cache') -Resume:$Resume -RetryFailed:$RetryFailed
exit $LASTEXITCODE
'@ | Set-Content $driver -Encoding UTF8
    function Invoke-Case($name,$scenario,$expected,[switch]$Resume,[switch]$RetryFailed) {
        $directory=Join-Path $sandbox $name; New-Item -ItemType Directory $directory -Force | Out-Null
        $parameters=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$driver,'-Installer',$installer,'-Sandbox',$directory,'-Scenario',$scenario)
        if($Resume) { $parameters+='-Resume' }; if($RetryFailed) { $parameters+='-RetryFailed' }
        $savedPreference=$ErrorActionPreference
        try { $ErrorActionPreference='Continue'; $output=& $shell @parameters 2>&1 | Out-String; $caseExitCode=$LASTEXITCODE }
        finally { $ErrorActionPreference=$savedPreference }
        if($caseExitCode -ne $expected) { throw "$name/$scenario exit=$caseExitCode expected=$expected`n$output" }
        return $directory
    }
    $case=Invoke-Case success success 0
    $autoCase=Invoke-Case auto auto 0
    $events=@(Get-Content (Join-Path $autoCase 'events'))
    if($events[0] -ne 'bootstrap' -or [array]::IndexOf($events,'install aria2') -lt 0 -or [array]::IndexOf($events,'install gh') -le [array]::IndexOf($events,'install aria2')) { throw 'Default path did not prepare Scoop/aria2 before installing apps' }
    if(Test-Path (Join-Path $autoCase 'installs')) { throw 'Default path used Winget for a Scoop-compatible app' }
    $autoState=Get-Content (Join-Path $autoCase 'state/install-state.json') -Raw | ConvertFrom-Json
    if($autoState.packages.'GitHub.cli'.provider -ne 'scoop') { throw 'Default provider was not Scoop' }
    $autoFailed=Invoke-Case auto-fail auto-fail 1
    if(Test-Path (Join-Path $autoFailed 'installs')) { throw 'Scoop bootstrap failure silently fell back to Winget' }
    $null=Invoke-Case success success 0 -Resume
    if(@(Get-Content (Join-Path $case 'installs')).Count -ne 1) { throw 'Resume reinstalled a verified package' }
    $resumePlan=& $shell -NoProfile -ExecutionPolicy Bypass -File $installer -Resume -Plan -StateDirectory (Join-Path $case 'state') 2>&1 | Out-String
    if($LASTEXITCODE -ne 0 -or $resumePlan -notlike '*GitHub CLI (GitHub.cli)*' -or $resumePlan -like '*Rustlang.Rustup*' -or $resumePlan -like '*Valve.Steam*') { throw "Resume did not restore the previous selection: $resumePlan" }
    $null=Invoke-Case false false-success 1
    $falseState=Get-Content (Join-Path $sandbox 'false/state/install-state.json') -Raw | ConvertFrom-Json
    if($falseState.packages.'GitHub.cli'.message -notlike '*ExitCode=0; Log=*package-*GitHub.cli.log*') { throw 'Per-package diagnostics missing for false success' }
    $case=Invoke-Case retry fail 1
    $null=Invoke-Case retry success 0 -RetryFailed
    $state=Get-Content (Join-Path $case 'state/install-state.json') -Raw | ConvertFrom-Json
    if($state.packages.'GitHub.cli'.status -ne 'installed') { throw 'Retry did not persist success' }
    $case=Invoke-Case interrupted interrupted 130
    $null=Invoke-Case interrupted success 0 -RetryFailed
    $state=Get-Content (Join-Path $case 'state/install-state.json') -Raw | ConvertFrom-Json
    if($state.packages.'GitHub.cli'.status -ne 'installed' -or $state.packages.'Microsoft.PowerToys'.status -ne 'installed') { throw 'Interrupted run lost its not-yet-started apps' }
    $case=Invoke-Case dependency dependency 1
    $state=Get-Content (Join-Path $case 'state/install-state.json') -Raw | ConvertFrom-Json
    if($state.packages.'Composer.Composer'.status -ne 'blocked') { throw 'Dependency failure did not block Composer' }
    if(@(Get-Content (Join-Path $case 'installs')).Count -ne 1) { throw 'Dependent app installed after failed prerequisite' }
    $legacy=Join-Path (Split-Path $installer) 'winstall-dougkusanagi-basic.ps1'
    $legacyOutput=& $shell -NoProfile -ExecutionPolicy Bypass -File $legacy -Profiles cli -Plan 2>&1 | Out-String
    if($LASTEXITCODE -ne 0 -or $legacyOutput -notlike '*ripgrep*') { throw "Legacy launcher bypassed the unified installer: $legacyOutput" }
    $commaPlan=& $shell -NoProfile -ExecutionPolicy Bypass -File $installer -Apps 'GitHub.cli,sharkdp.bat' -Plan 2>&1 | Out-String
    if($LASTEXITCODE -ne 0 -or $commaPlan -notlike '*GitHub CLI*' -or $commaPlan -notlike '*bat (sharkdp.bat)*' -or $commaPlan -like '*Rustlang.Rustup*') { throw "Comma-separated native launcher arguments failed: $commaPlan" }
    Write-Host 'PASS: isolated installer verification, resume, retry failed steps and dependency failure propagation.'
} finally { Remove-Item -LiteralPath $sandbox -Recurse -Force }
exit 0
