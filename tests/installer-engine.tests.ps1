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
    $script:scoopPrefix=Join-Path $sandbox 'scoop-package'
    $script:scoopInstalls=0
    function scoop {
        if($args[0] -eq 'prefix') {
            if(Test-Path $script:scoopPrefix) { $global:LASTEXITCODE=0; $script:scoopPrefix }
            else { $global:LASTEXITCODE=1 }
            return
        }
        $script:scoopInstalls++; New-Item -ItemType Directory $script:scoopPrefix -Force | Out-Null; $global:LASTEXITCODE=0
    }
    function Get-Command {
        param($Name,$ErrorAction)
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
