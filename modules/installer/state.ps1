function Get-GuepardoFingerprint {
    param($Definition)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Definition | ConvertTo-Json -Depth 20 -Compress))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-GuepardoState {
    param([string]$Path)
    $state = @{ schemaVersion = 1; packages = @{} }
    if (Test-Path -LiteralPath $Path) {
        try {
            $saved = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            if ($saved.schemaVersion -ne 1) { throw 'Unsupported state version' }
            foreach ($property in $saved.packages.PSObject.Properties) { $state.packages[$property.Name] = $property.Value }
        } catch { throw "Cannot read installer state $Path. Preserve it for diagnosis or choose another -StateDirectory. $_" }
    }
    return $state
}

function Save-GuepardoState {
    param($State, [string]$Path)
    $temporary = "$Path.$PID.tmp"
    try {
        $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporary -Encoding UTF8
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, "$Path.bak") }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Set-GuepardoPackageState {
    param($State, [string]$Path, $Package, [string]$Status, [string]$Provider, [string]$Message = '')
    $State.packages[$Package.Id] = @{
        status = $Status; provider = $Provider; fingerprint = Get-GuepardoFingerprint $Package.Definition
        updatedAt = [DateTime]::UtcNow.ToString('o'); message = $Message
    }
    Save-GuepardoState $State $Path
}

function Enter-GuepardoLock {
    param([string]$Directory)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    try { return [IO.File]::Open((Join-Path $Directory 'installer.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw "Another installer is using $Directory. Close it before retrying." }
}
