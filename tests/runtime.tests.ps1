$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../modules/installer/runtime.ps1')
. (Join-Path $PSScriptRoot '../modules/installer/ui.ps1')
function Assert($ok,$message) { if(-not $ok){throw $message} }
$release=[pscustomobject]@{tag_name='v7.9.1';prerelease=$false;draft=$false;assets=@([pscustomobject]@{name='PowerShell-7.9.1-win-arm64.zip';browser_download_url='https://github.com/PowerShell/PowerShell/releases/download/v7.9.1/PowerShell-7.9.1-win-arm64.zip'})}
Assert ((Get-GuepardoPowerShellAsset $release arm64).Version -eq '7.9.1') 'Stable release/ARM64 selection failed'
$release.prerelease=$true;$thrown=$false;try {Get-GuepardoPowerShellAsset $release arm64}catch{$thrown=$true};Assert $thrown 'Preview release accepted';$release.prerelease=$false
$thrown=$false;try {Get-GuepardoPowerShellAsset $release x64}catch{$thrown=$true};Assert $thrown 'Missing architecture accepted'
$hash='a'*64
$realManifest=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/powershell-7.6.9-hashes.sha256'))
Assert ((Get-GuepardoRuntimeChecksum $realManifest 'PowerShell-7.6.9-win-x64.zip') -eq 'ce7484804c0f0ad4dda10c958e71acdaf7eebfb22505c1b480f89e0e9f1da94d') 'Real UTF-16LE release manifest cannot be parsed'
Assert ((Get-GuepardoRuntimeChecksum (([string][char]0xFEFF)+$hash+" *asset.zip`r`n") 'asset.zip') -eq $hash) 'BOM on first checksum line rejected'
Assert ((Get-GuepardoRuntimeChecksum "$hash *PowerShell-7.9.1-win-arm64.zip" 'PowerShell-7.9.1-win-arm64.zip') -eq $hash) 'SHA256 manifest parsing failed'
$thrown=$false;try {Get-GuepardoRuntimeChecksum 'invalid' 'asset.zip'}catch{$thrown=$true};Assert $thrown 'Missing checksum accepted'
Assert ((Format-GuepardoPickerText '[x] [ ] [-]') -eq (([string][char]0x2611)+' '+([string][char]0x2610)+' '+([string][char]0x25A3))) 'Unicode checkboxes missing'
Assert ((Format-GuepardoPickerText '[x] [ ]' -Plain) -eq '[x] [ ]') 'Plain checkbox fallback broken'
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('guepardo-runtime-test-'+[guid]::NewGuid())
New-Item -ItemType Directory $sandbox | Out-Null
$savedMarker=$env:GUEPARDO_RUNTIME_HOST
try {
    $script:runtimeTestExe=(Get-Command pwsh.exe -ErrorAction Stop).Source
    function Install-GuepardoPowerShellRuntime { return $script:runtimeTestExe }
    $installer=Join-Path $sandbox "argument test ' space.ps1"
    $output=Join-Path $sandbox 'result.clixml'
    @'
param([string[]]$Apps,[switch]$Resume,[string]$StateDirectory)
@{Apps=$Apps;Resume=[bool]$Resume;HostVersion=$PSVersionTable.PSVersion.Major;Marker=$env:GUEPARDO_RUNTIME_HOST} | Export-Clixml -LiteralPath $StateDirectory
exit 23
'@ | Set-Content -LiteralPath $installer
    $code=Invoke-GuepardoPowerShellRuntime $installer @{Apps=@('one','two with space');Resume=[Management.Automation.SwitchParameter]::new($true);StateDirectory=$output}
    $result=Import-Clixml -LiteralPath $output
    Assert ($code -eq 23 -and $result.Resume -and $result.HostVersion -ge 7) 'Relaunch exit/switch/runtime lost'
    Assert (($result.Apps -join '|') -eq 'one|two with space') 'Relaunch array arguments corrupted'
    Assert ($result.Marker -eq $script:runtimeTestExe -and $env:GUEPARDO_RUNTIME_HOST -eq $savedMarker) 'Runtime marker not restored'
    @'
param([string]$StateDirectory)
$child=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoLogo -NoProfile -Command Start-Sleep -Seconds 30' -WindowStyle Hidden -PassThru
Set-Content -LiteralPath $StateDirectory -Value $child.Id
exit 0
'@ | Set-Content -LiteralPath $installer
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $code=Invoke-GuepardoPowerShellRuntime $installer @{StateDirectory=$output}
    $childId=[int](Get-Content -LiteralPath $output)
    try { Assert ($code -eq 0 -and $timer.Elapsed.TotalSeconds -lt 15) 'Bootstrap waited for background descendants after installer exit' }
    finally { Stop-Process -Id $childId -ErrorAction SilentlyContinue }
} finally {
    $target=[IO.Path]::GetFullPath($sandbox)
    Assert ($target.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))) 'Unsafe cleanup'
    Remove-Item -LiteralPath $target -Recurse -Force
}
Write-Host 'PASS: stable runtime assets, checksums, Unicode/plain UI and real child-process argument/exit preservation.'
