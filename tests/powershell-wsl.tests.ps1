$ErrorActionPreference='Stop'
function Assert($ok,$message) { if (-not $ok) { throw $message } }
. "$PSScriptRoot/../modules/installer/catalog.ps1"
. "$PSScriptRoot/../modules/installer/providers.ps1"
$catalog=Get-GuepardoCatalog
$package=@(Resolve-GuepardoPlan $catalog @('cli') @() @() | Where-Object Id -eq 'Microsoft.PowerShell')[0]
Assert ($package.Definition.windows.scoop -eq 'pwsh' -and $package.Definition.windows.alwaysUpdate) 'PowerShell update metadata missing'
Assert (-not $package.Definition.linux) 'PowerShell must be Windows only'
Assert (@(Resolve-GuepardoPlan $catalog @('wsl2') @() @() | Where-Object Id -eq 'Microsoft.PowerShell').Count -eq 0) 'WSL must not depend on PowerShell'
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../install.ps1'),[ref]$null,[ref]$null)
Invoke-Expression ($ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-InstallResult'},$true).Extent.Text)
$wsl=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Install-Wsl'},$true)
$child=$wsl.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -like '*function Invoke-WslStep*'},$true).Value
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-wsl-tests-'+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
try {
    function winget { $script:wingetArgs=@($args); $global:LASTEXITCODE=0 }
    $null=Invoke-GuepardoManagedInstall $package winget (Join-Path $sandbox 'provider.log')
    Assert ('--no-upgrade' -notin $script:wingetArgs) 'PowerShell updates disabled'
    $ordinary=@(Resolve-GuepardoPlan $catalog @() @('GitHub.cli') @())[0]
    $null=Invoke-GuepardoManagedInstall $ordinary winget (Join-Path $sandbox 'provider.log')
    Assert ('--no-upgrade' -in $script:wingetArgs) 'Ordinary package flag was split into characters or lost'
    function Test-GuepardoPackage { return $true }
    function scoop { $script:scoopArgs=@($args); $global:LASTEXITCODE=0 }
    $null=Invoke-GuepardoManagedInstall $package scoop (Join-Path $sandbox 'provider.log')
    Assert ($script:scoopArgs[0] -eq 'update' -and $script:scoopArgs[1] -eq 'pwsh') 'Scoop PowerShell not updated'
    foreach($scenario in @('success','fallback','failure','pending','reboot','already2','unknown-version','conversion-failure')) {
        $trace=Join-Path $sandbox "$scenario.trace"
        $log=Join-Path $sandbox "$scenario.log"
        $setup=@'
function Get-WindowsOptionalFeature { if($scenario -eq 'pending'){ @{State='EnablePending'} }else{ @{State='Enabled'} } }
function Enable-WindowsOptionalFeature { @{RestartNeeded=($scenario -eq 'reboot')} }
function Fake-Wsl {
    ($args -join ' ') | Add-Content -LiteralPath $trace
    $global:LASTEXITCODE=0
    if($args[0] -eq '--list'){
        if($args[1] -eq '--verbose') {
            if($scenario -eq 'unknown-version') { 'Ubuntu estado desconhecido'; return }
            if($scenario -eq 'already2') { "* Ubuntu Em Execução 2".ToCharArray() -join ([string][char]0); return }
            '  Ubuntu Stopped 1'; return
        }
        if($scenario -eq 'already2'){ 'Ubuntu' }; return
    }
    if($args[0] -eq '--set-version' -and $scenario -in @('already2','conversion-failure')) { $global:LASTEXITCODE=-1; 'simulated conversion error' }
    if($args[0] -eq '--update' -and ($scenario -eq 'failure' -or ($scenario -eq 'fallback' -and '--web-download' -notin $args))) { $global:LASTEXITCODE=-1; 'simulated update error' }
}
'@
        $driver=Join-Path $sandbox "$scenario.ps1"
        $prefix='$scenario='''+$scenario+'''; $trace='''+$trace.Replace("'","''")+"'`n"
        Set-Content $driver ($prefix+$setup+"`n"+$child.Replace('__WSL_LOG__',$log.Replace("'","''")).Replace('& $wsl','& Fake-Wsl'))
        & (Get-Process -Id $PID).Path -NoProfile -File $driver *> $null
        $code=$LASTEXITCODE
        if($scenario -in @('pending','reboot')) {
            Assert ($code -eq 3010 -and -not (Test-Path $trace)) 'Reboot must defer WSL commands'
        } elseif($scenario -in @('unknown-version','conversion-failure')) {
            Assert ($code -eq 1) 'Unknown version or genuine conversion failure swallowed'
        } elseif($scenario -eq 'failure') {
            Assert ($code -eq 1) 'WSL failure swallowed'
            Assert ((Get-Content $log -Raw) -like '*simulated update error*') 'WSL diagnostic missing'
        } else {
            Assert ($code -eq 0) "WSL scenario failed: $scenario"
            $calls=Get-Content $trace
            Assert ($calls[0] -eq '--update') 'WSL must update before Ubuntu install'
            Assert ($calls[-1] -eq '--set-default Ubuntu') 'WSL configuration incomplete'
            if($scenario -eq 'fallback') { Assert ($calls[1] -eq '--update --web-download') 'Web download fallback missing' }
            if($scenario -eq 'already2') {
                Assert (-not ($calls -like '--set-version *')) 'Already WSL2 Ubuntu was converted again'
                Assert (-not ($calls -like '--install *')) 'Existing Ubuntu was installed again'
            } else { Assert ([bool]($calls -like '--set-version Ubuntu 2')) 'WSL1 Ubuntu was not converted'
            }
        }
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($sandbox)
    Assert ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))) 'Unsafe cleanup path'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
'PASS: Windows-only PowerShell updates and WSL success/fallback/failure/reboot scenarios'
