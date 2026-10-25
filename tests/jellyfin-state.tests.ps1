$ErrorActionPreference='Stop'
. "$PSScriptRoot/../modules/installer/state.ps1"
function Assert($ok,$message) { if(-not $ok){throw $message} }
$package=@{Id='guepardo.jellyfin-config';Definition=@{id='guepardo.jellyfin-config';dependsOn=@('Jellyfin.Server')}}
$previous=@{status='installed';fingerprint=Get-GuepardoFingerprint $package.Definition}
$results=@{'Jellyfin.Server'='already-installed'}
Assert (Test-GuepardoCompletedJellyfinConfiguration $package $previous $results) 'Successful configuration repeated'
$previous.status='already-installed'
Assert (Test-GuepardoCompletedJellyfinConfiguration $package $previous $results) 'Third execution repeated configuration'
Assert (-not (Test-GuepardoCompletedJellyfinConfiguration $package $previous $results -Reconfigure)) 'Explicit reconfiguration ignored'
foreach($status in @('failed','running','blocked','reboot-required')) {
    $previous.status=$status
    Assert (-not (Test-GuepardoCompletedJellyfinConfiguration $package $previous $results)) "Incomplete configuration skipped: $status"
}
$previous.status='installed';$previous.fingerprint='old'
Assert (-not (Test-GuepardoCompletedJellyfinConfiguration $package $previous $results)) 'Changed definition skipped'
$previous.fingerprint=Get-GuepardoFingerprint $package.Definition
$results['Jellyfin.Server']='installed'
Assert (-not (Test-GuepardoCompletedJellyfinConfiguration $package $previous $results)) 'New server installation skipped configuration'
Assert (-not (Test-GuepardoCompletedJellyfinConfiguration $package $null $results)) 'First configuration skipped'
Write-Host 'PASS: Jellyfin config reuse, repeated runs, explicit reconfiguration, failures and server reinstall.'
