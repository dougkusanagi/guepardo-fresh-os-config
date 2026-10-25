$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../modules/installer/ui.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
$catalog=[pscustomobject]@{
    profiles=@(
        [pscustomobject]@{id='cli';label='Terminal';platforms=@('windows')},
        [pscustomobject]@{id='desktop';label='Desktop';platforms=@('windows')}
    )
    apps=@(
        [pscustomobject]@{id='a';name='App A';profiles=@('cli')},
        [pscustomobject]@{id='b';name='App B';profiles=@('cli')},
        [pscustomobject]@{id='c';name='App C';profiles=@('desktop')}
    )
}
$render=${function:Write-GuepardoPicker}
$script:frames=@()
function Write-GuepardoPicker {
    param($Rows,$Active,$Height,$Width,$Count,$Message,[switch]$NoColor)
    $script:frames+=@{Active=$Active;Rows=$Rows;Count=$Count;Message=$Message}
}
function Invoke-Keys([string[]]$Keys) {
    $script:keys=New-Object 'System.Collections.Generic.Queue[object]'
    foreach($name in $Keys) {
        $key=[Enum]::Parse([ConsoleKey],$name)
        $script:keys.Enqueue([ConsoleKeyInfo]::new([char]0,$key,$false,$false,$false))
    }
    $script:frames=@()
    return @(Select-GuepardoApps -Catalog $catalog -NoColor -ReadKey { $script:keys.Dequeue() })
}
foreach($case in @(
    @{Keys=@('DownArrow','Spacebar','Enter');Want='c'},
    @{Keys=@('UpArrow','Spacebar','Enter');Want='c'},
    @{Keys=@('Spacebar','Enter');Want='a,b'},
    @{Keys=@('Spacebar','Spacebar','DownArrow','Spacebar','Enter');Want='c'},
    @{Keys=@('RightArrow','DownArrow','Spacebar','Enter');Want='a'},
    @{Keys=@('RightArrow','DownArrow','DownArrow','Spacebar','LeftArrow','DownArrow','Spacebar','Enter');Want='b,c'},
    @{Keys=@('Enter','DownArrow','Spacebar','Enter');Want='c'},
    @{Keys=@('T','T','DownArrow','Spacebar','Enter');Want='c'},
    @{Keys=@('End','Spacebar','Home','RightArrow','DownArrow','Spacebar','Enter');Want='a,c'},
    @{Keys=@('PageDown','Spacebar','Enter');Want='c'},
    @{Keys=@('End','PageUp','Spacebar','Enter');Want='a,b'}
)) {
    $result=@(Invoke-Keys $case.Keys)
    Assert (($result -join ',') -eq $case.Want) "Keyboard selection failed: $($case.Keys -join ',') => $($result -join ',')"
}
foreach($cancel in @('Escape','Q')) {
    $cancelled=$false
    try { $null=Invoke-Keys @($cancel) } catch [OperationCanceledException] { $cancelled=$true }
    Assert $cancelled "Cancel key $cancel was ignored"
}
$catalog.apps+= [pscustomobject]@{id='shared';name='Shared app';profiles=@('cli','desktop')}
$result=@(Invoke-Keys @('Spacebar','DownArrow','Spacebar','Enter'))
Assert ($result.Count -eq 4 -and @($result|Select-Object -Unique).Count -eq 4) 'An app shared by two profiles was duplicated'
for($active=0;$active -lt 80;$active++) {
    foreach($height in @(12,20,32)) {
        $view=Get-GuepardoPickerViewport 80 $active $height
        Assert ($view.First -le $active -and $view.Last -ge $active -and $view.Last -lt 80) 'Focused item disappeared from the viewport'
        Assert (($view.Last-$view.First+1) -le [Math]::Max(1,$height-11)) 'Picker overflowed its viewport'
    }
}
$rows=@(Get-GuepardoPickerRows $catalog @{} @{})
$preview=& $render -Rows $rows -Active 0 -Height 25 -Width 80 -Count 0 -Message '' -NoColor 6>&1 | Out-String
Assert ($preview -like '*Espaco: marcar*' -and $preview -like '*Enter: continuar*' -and $preview -match '>\s+\[') 'Keyboard instructions or focus marker are missing'
Assert ($preview -notmatch '\x1b\[') 'Plain output contains ANSI escapes'
Write-Host 'PASS: real ConsoleKeyInfo events, arrows, Space, expand/collapse, toggles, confirmation, cancellation and scrolling.'
exit 0
