$ErrorActionPreference='Stop'
foreach ($module in @('catalog','state','providers','ui')) { . (Join-Path $PSScriptRoot "../modules/installer/$module.ps1") }
function Assert($condition,$message) { if (-not $condition) { throw $message } }
function Assert-Throws([scriptblock]$action,$message) { $thrown=$false; try { & $action } catch { $thrown=$true }; Assert $thrown $message }
$catalog=Get-GuepardoCatalog
$plan=@(Resolve-GuepardoPlan $catalog @() @('Composer.Composer') @())
Assert ($plan.Count -eq 2 -and $plan[0].Id -eq 'PHP.PHP.8.4') 'Dependency order is invalid'
Assert-Throws { Resolve-GuepardoPlan $catalog @() @('Composer.Composer') @('PHP.PHP.8.4') } 'Excluded dependency accepted'
Assert-Throws { Resolve-GuepardoPlan $catalog @() @('missing') @() } 'Unknown app accepted'
$bad=Get-GuepardoCatalog; $bad.apps[0].dependsOn=@($bad.apps[0].id)
Assert-Throws { Resolve-GuepardoPlan $bad @() @($bad.apps[0].id) @() } 'Dependency cycle accepted'
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-engine-'+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
try {
    $path=Join-Path $sandbox 'state.json'; $state=Read-GuepardoState $path
    Set-GuepardoPackageState $state $path $plan[0] 'running' 'winget'
    Set-GuepardoPackageState $state $path $plan[0] 'installed' 'winget'
    $saved=Read-GuepardoState $path
    Assert ($saved.packages['PHP.PHP.8.4'].status -eq 'installed') 'State round trip failed'
    Assert (Test-Path "$path.bak") 'Previous atomic state not preserved'
    $lock=Enter-GuepardoLock $sandbox
    try { Assert-Throws { $unexpected=Enter-GuepardoLock $sandbox; $unexpected.Dispose() } 'Concurrent installers accepted' } finally { $lock.Dispose() }
    Set-Content $path '{invalid'
    Assert-Throws { Read-GuepardoState $path } 'Corrupted state silently accepted'
    $functionAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../install.ps1'),[ref]$null,[ref]$null).Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-InstallResult' },$true)
    Invoke-Expression $functionAst.Extent.Text
    $script:calls=0; $script:fakeCode=12002
    function winget { $script:calls++; $global:LASTEXITCODE=$script:fakeCode }
    function Start-Sleep { param($Seconds) }
    $code=Invoke-GuepardoManagedInstall $plan[0] winget (Join-Path $sandbox 'log') -Attempts 3
    Assert ($script:calls -eq 3 -and $code -eq 12002) 'Transient download was not retried'
    $script:calls=0; $script:fakeCode=1603
    $code=Invoke-GuepardoManagedInstall $plan[0] winget (Join-Path $sandbox 'log') -Attempts 3
    Assert ($script:calls -eq 1) 'Permanent installer failure retried'
    $script:calls=0
    $code=Invoke-GuepardoManagedInstall $plan[0] winget (Join-Path $sandbox 'log') -InteractiveFallback
    Assert ($script:calls -eq 2) 'Explicit interactive fallback missing'
    $script:scoopPrefix=Join-Path $sandbox 'scoop/apps/gh/current'
    $script:scoopInstalls=0
    $script:scoopConfigs=@()
    $script:ariaReady=$false; $script:bucketAdds=0
    $script:testScoopRoot=Join-Path $sandbox 'scoop'
    function Get-GuepardoScoopRoot { return $script:testScoopRoot }
    function scoop {
        if($args[0] -eq 'config') { $script:scoopConfigs+="$($args[1])=$($args[2])"; $global:LASTEXITCODE=0; return }
        if($args[0] -eq 'bucket') { $script:bucketAdds++; New-Item -ItemType Directory (Join-Path $script:testScoopRoot 'buckets/extras') -Force | Out-Null; $global:LASTEXITCODE=0; return }
        if($args[0] -eq 'prefix') {
            if(Test-Path $script:scoopPrefix) { $global:LASTEXITCODE=0; $script:scoopPrefix }
            else { $global:LASTEXITCODE=1 }
            return
        }
        if($args[1] -eq 'aria2') {
            $script:ariaReady=$true
            $binary=Join-Path $script:testScoopRoot 'apps/aria2/current/aria2c.exe'
            New-Item -ItemType Directory (Split-Path $binary) -Force | Out-Null; Set-Content $binary '# fake aria2'
        }
        $script:scoopInstalls++; New-Item -ItemType Directory $script:scoopPrefix -Force | Out-Null; $global:LASTEXITCODE=0
    }
    function Get-Command {
        param($Name,$ErrorAction)
        if($Name -eq 'aria2c' -and $script:ariaReady) { return @{Name=$Name;Source=$Name} }
        if($Name -eq 'scoop' -or ($Name -eq 'gh' -and (Test-Path $script:scoopPrefix))) { return @{Name=$Name;Source=$Name} }
        return $null
    }
    $scoopPackage=@(Resolve-GuepardoPlan $catalog @() @('GitHub.cli') @())[0]
    Assert ((Get-GuepardoProvider $scoopPackage auto) -eq 'scoop') 'Auto did not select available Scoop'
    Assert (-not (Test-GuepardoPackage $scoopPackage scoop)) 'Missing Scoop package accepted'
    $code=Invoke-GuepardoManagedInstall $scoopPackage scoop (Join-Path $sandbox 'scoop.log')
    Assert ($code -eq 0 -and (Test-GuepardoPackage $scoopPackage scoop)) 'Scoop install/verification failed'
    Install-GuepardoScoop $sandbox
    Assert ($script:scoopInstalls -eq 2) 'Existing Scoop did not prepare aria2'
    Assert ('aria2-enabled=true' -in $script:scoopConfigs -and 'aria2-fallback-enabled=true' -in $script:scoopConfigs) 'aria2 was not enabled with fallback'
    Install-GuepardoScoop $sandbox -Buckets extras
    Install-GuepardoScoop $sandbox -Buckets extras
    Assert ($script:bucketAdds -eq 1 -and $script:scoopInstalls -eq 3) 'Extras/Git preparation is missing or not idempotent'
    function Receive-GuepardoFile { param($Uri,$Destination,$CacheDirectory,$MaxAgeSeconds) Set-Content $Destination '# fake bootstrap' }
    function Test-GuepardoAdministrator { return $script:adminCase }
    function powershell.exe { $script:coldArgs=@($args); $script:scoopReady=$true; $global:LASTEXITCODE=0 }
    function Get-Command {
        param($Name,$ErrorAction)
        if($Name -eq 'scoop' -and ($script:scoopReady -or ((Test-Path (Join-Path $script:testScoopRoot 'shims/scoop.ps1')) -and (Join-Path $script:testScoopRoot 'shims') -in $env:Path.Split(';')))) { return @{Name=$Name;Source=$Name} }
        if($Name -eq 'aria2c' -and $script:ariaReady) { return @{Name=$Name;Source=$Name} }
        return $null
    }
    foreach($admin in @($false,$true)) {
        $script:adminCase=$admin; $script:scoopReady=$false; $script:ariaReady=$false
        Remove-Item -LiteralPath (Join-Path $script:testScoopRoot 'apps/aria2/current/aria2c.exe') -Force
        Install-GuepardoScoop $sandbox
        Assert ($script:scoopReady -and $script:ariaReady) 'Cold bootstrap did not prepare Scoop/aria2'
        Assert (('-RunAsAdmin' -in $script:coldArgs) -eq $admin) 'Bootstrap elevation option is incorrect'
    }
    $shims=Join-Path $script:testScoopRoot 'shims'
    New-Item -ItemType Directory $shims -Force | Out-Null
    Set-Content (Join-Path $shims 'scoop.ps1') '# fake existing Scoop'
    $savedPath=$env:Path
    try {
        $env:Path=($env:Path.Split(';') | Where-Object { $_ -ne $shims }) -join ';'
        $script:scoopReady=$false; $script:coldArgs=@()
        Install-GuepardoScoop $sandbox
        Assert ($script:coldArgs.Count -eq 0 -and $shims -in $env:Path.Split(';')) 'Existing Scoop was reinstalled because the parent terminal had a stale PATH'
    } finally { $env:Path=$savedPath }
    # Package names need not match executable names (verified against publisher manifests).
    function Get-Command {
        param($Name,$ErrorAction)
        if($Name -in @('rg','btm','tldr')) { return @{Name=$Name;Source=$Name} }
        return $null
    }
    foreach($id in @('BurntSushi.ripgrep.MSVC','Clement.bottom','dbrgn.tealdeer')) {
        $script:registeredId=$id
        function winget { $global:LASTEXITCODE=0; "$script:registeredId 1.0" }
        $package=@(Resolve-GuepardoPlan $catalog @() @($id) @())[0]
        Assert (Test-GuepardoPackage $package winget) "Valid executable was not recognized for $id"
    }
    $testCatalog=[pscustomobject]@{profiles=@([pscustomobject]@{id='cli';label='Terminal';platforms=@('windows')});apps=@([pscustomobject]@{id='one';name='App One';profiles=@('cli')})}
    $script:answers=New-Object 'System.Collections.Generic.Queue[string]'
    @('e 1','2','') | ForEach-Object { $script:answers.Enqueue($_) }
    function Read-Host { param($Prompt) return $script:answers.Dequeue() }
    $picked=@(Select-GuepardoApps $testCatalog -NoColor)
    Assert ($picked.Count -eq 1 -and $picked[0] -eq 'one') 'Individual app selection failed'
    Write-Host 'PASS: catalog, dependency order/cycles, atomic state, lock, corruption, retries and app selection.'
} finally { Remove-Item -LiteralPath $sandbox -Recurse -Force }
exit 0
