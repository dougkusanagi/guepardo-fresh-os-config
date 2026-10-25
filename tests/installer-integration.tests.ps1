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
$env:GUEPARDO_TEST_TRACE=Join-Path $Sandbox 'vite-environment.json'
function Get-Command {
    param([string]$Name,$ErrorAction)
    if($Name -eq 'curl.exe') { return @{Name='curl.exe';Source='curl.exe'} }
    if($Scenario -eq 'broken-winget' -and $Name -in @('gh','gh.exe','gh.cmd','gh.bat','gh.ps1')) {
        if(Test-Path (Join-Path $Sandbox 'scoop/apps/gh/current')) { return @{Name='gh';Source='fake-gh'} }; return $null
    }
    if($Scenario -eq 'vite-temp' -and $Name -in @('vp','vp.exe','vp.cmd','vp.bat','vp.ps1')) {
        if(Test-Path $env:GUEPARDO_TEST_TRACE) { return @{Name='vp';Source='vp'} }; return $null
    }
    if($Scenario -eq 'composer-cleanup' -and $Name -eq 'php') { return @{Name=$Name;Source=$Name} }
    if($Scenario -eq 'composer-cleanup' -and $Name -eq 'composer') {
        if($script:composerReady) { return @{Name=$Name;Source=$Name} }; return $null
    }
    if($Name -eq 'scoop') {
        if(Test-Path (Join-Path $Sandbox 'scoop-ready')) { return @{Name='scoop';Source=(Join-Path $env:SCOOP 'shims/scoop.ps1')} }
        return $null
    }
    if($Name -eq 'aria2c' -and (Test-Path (Join-Path $Sandbox 'aria-ready'))) { return @{Name='aria2c';Source='fake-aria2c'} }
    Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue
}
function curl.exe {
    $destination=$args[[array]::IndexOf($args,'--output')+1]
    if($Scenario -eq 'vite-temp') {
        Set-Content -LiteralPath $destination '$data=@{Temp=$env:TEMP;Tmp=$env:TMP;Path=$env:Path}; $data | ConvertTo-Json | Set-Content -LiteralPath $env:GUEPARDO_TEST_TRACE; exit 0'
    } else { Set-Content -LiteralPath $destination '# mocked Scoop installer' }
    $global:LASTEXITCODE=0
}
function vp { $global:LASTEXITCODE=0; 'vp 1.0' }
function Start-Process {
    param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru,[switch]$NoNewWindow)
    if($Scenario -ne 'composer-cleanup') { throw 'Unexpected native installer in fake test' }
    $script:composerReady=$true
    return @{ExitCode=0}
}
function Remove-Item {
    param($LiteralPath,$Path,[switch]$Force,[switch]$Recurse,$ErrorAction)
    $target=if($LiteralPath){$LiteralPath}else{$Path}
    if($Scenario -eq 'composer-cleanup' -and (Split-Path $target -Leaf) -match '^[a-f0-9]{8}-[a-f0-9]{4}-') { throw [UnauthorizedAccessException]::new('Simulated Composer installer lock') }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $target -Force:$Force -Recurse:$Recurse -ErrorAction Stop
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
        if((Test-Path $marker) -or $Scenario -eq 'broken-winget') { "$id 1.0"; $global:LASTEXITCODE=0 } else { $global:LASTEXITCODE=1 }
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
if($Scenario -eq 'composer-cleanup') { $apps=@('Composer.Composer','Microsoft.PowerToys') }
if($Scenario -eq 'vite-temp') { $apps=@('guepardo.vite-plus') }
if($Scenario -in @('auto','auto-fail','broken-winget')) {
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
    $repaired=Invoke-Case repair broken-winget 0
    $repairState=Get-Content (Join-Path $repaired 'state/install-state.json') -Raw | ConvertFrom-Json
    if($repairState.packages.'GitHub.cli'.provider -ne 'scoop' -or $repairState.packages.'GitHub.cli'.status -ne 'installed') { throw 'Broken registered Winget CLI was not repaired with Scoop' }
    $viteCase=Invoke-Case vite vite-temp 0
    $childEnvironment=Get-Content (Join-Path $viteCase 'vite-environment.json') -Raw | ConvertFrom-Json
    if(-not $childEnvironment.Temp.StartsWith((Join-Path $viteCase 'state/Temp')) -or $childEnvironment.Temp -ne $childEnvironment.Tmp) { throw 'Vite inherited an unsafe/system TEMP directory' }
    $composerCase=Invoke-Case composer composer-cleanup 0
    $composerState=Get-Content (Join-Path $composerCase 'state/install-state.json') -Raw | ConvertFrom-Json
    if($composerState.packages.'Composer.Composer'.status -ne 'installed' -or $composerState.packages.'Microsoft.PowerToys'.status -ne 'installed') { throw 'Locked Composer cleanup prevented the remaining apps from running' }
    $profileFile=Join-Path $case 'profile.ps1'
    Set-Content $profileFile "# user content preserved`n# region Guepardo Fresh OS Config Shortcuts`nfunction refreshenv { throw 'legacy refresh' }`n# endregion"
    $null=Invoke-Case success success 0 -Resume
    $profileText=Get-Content $profileFile -Raw
    if($profileText -notlike '*# user content preserved*' -or $profileText -notlike '*Guepardo Environment Refresh v2*') { throw 'Existing managed profile was not safely upgraded' }
    $profileAst=[Management.Automation.Language.Parser]::ParseFile($profileFile,[ref]$null,[ref]$null)
    $refreshFunctions=@($profileAst.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'refreshenv'},$true))
    Invoke-Expression $refreshFunctions[-1].Extent.Text
    $preservedTemp=$env:TEMP; refreshenv | Out-Null
    if($env:TEMP -ne $preservedTemp) { throw 'Generated refreshenv still overwrites user TEMP' }
    if(@(Get-Content (Join-Path $case 'installs')).Count -ne 1) { throw 'Resume reinstalled a verified package' }
    $resumePlan=& $shell -NoProfile -ExecutionPolicy Bypass -File $installer -Resume -Plan -StateDirectory (Join-Path $case 'state') 2>&1 | Out-String
    if($LASTEXITCODE -ne 0 -or $resumePlan -notlike '*GitHub CLI (GitHub.cli)*' -or $resumePlan -like '*Rustlang.Rustup*' -or $resumePlan -like '*Valve.Steam*') { throw "Resume did not restore the previous selection: $resumePlan" }
    $legacyState=Get-Content (Join-Path $case 'state/install-state.json') -Raw | ConvertFrom-Json
    $legacyState.selection=@($legacyState.selection)+@('Microsoft.VisualStudioCode')
    $legacyState.packages | Add-Member -MemberType NoteProperty -Name 'Microsoft.VisualStudioCode' -Value @{status='failed'}
    $legacyState | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $case 'state/install-state.json') -Encoding UTF8
    $retiredPlan=& $shell -NoProfile -ExecutionPolicy Bypass -File $installer -Resume -Plan -StateDirectory (Join-Path $case 'state') 2>&1 | Out-String
    if($LASTEXITCODE -ne 0 -or $retiredPlan -like '*Microsoft.VisualStudioCode*' -or $retiredPlan -notlike '*GitHub CLI*') { throw 'A retired editor broke resuming the remaining apps' }
    $null=Invoke-Case success success 0 -RetryFailed
    if(@(Get-Content (Join-Path $case 'installs')).Count -ne 1) { throw 'Retry installed apps after the only failure was retired VS Code' }
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
