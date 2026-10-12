<#
.SYNOPSIS
    Compatibility launcher for the Go Windows installer.
.DESCRIPTION
    Forwards Windows installer options to cmd/guepardo. The OneDrive bootstrap
    can provision Go and the repository before compiling this executable.
#>
[CmdletBinding()]
param (
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$InstallerArguments
)

$ErrorActionPreference = 'Stop'
$go = Get-Command go.exe -ErrorAction SilentlyContinue
if (-not $go) {
    Write-Error 'Go 1.22 ou superior não foi encontrado. Execute install.cmd pelo OneDrive ou instale o Go.'
    exit 1
}

$forwarded = foreach ($argument in $InstallerArguments) {
    switch -Regex ($argument) {
        '(?i)^-Profiles$' { '--profiles'; break }
        '(?i)^-Mode$' { '--mode'; break }
        '(?i)^-Plan$' { '--plan'; break }
        '(?i)^-DryRun$' { '--dry-run'; break }
        '(?i)^-ListProfiles$' { '--list-profiles'; break }
        '(?i)^-ListThemes$' { '--list-themes'; break }
        '(?i)^-Help$' { '--help'; break }
        default { $argument }
    }
}

Push-Location $PSScriptRoot
try {
    & $go.Source run ./cmd/guepardo @forwarded
    $installerExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $installerExitCode
