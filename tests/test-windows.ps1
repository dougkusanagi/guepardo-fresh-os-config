# Windows installer tests

$ErrorActionPreference = "Stop"

$testsFailed = 0
$testsPassed = 0

function Assert-True {
    param (
        [bool]$Condition,
        [string]$Message
    )
    if ($Condition) {
        Write-Host "PASS: $Message" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "FAIL: $Message" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host "=== Running Windows Installer Tests ===" -ForegroundColor Cyan

# Test 1: Check file existence
$installScript = Join-Path $PSScriptRoot "..\install.ps1"
Assert-True (Test-Path $installScript) "install.ps1 file exists at the root directory"

# Test 2: Syntax validation
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($installScript, [ref]$tokens, [ref]$errors)
Assert-True ($errors.Count -eq 0) "install.ps1 has no PowerShell syntax errors"
if ($errors.Count -gt 0) {
    foreach ($err in $errors) {
        Write-Host "  Syntax Error: $($err.Message) at line $($err.Extent.StartLineNumber)" -ForegroundColor Red
    }
}

# Test 3: Dry-run execution
Write-Host "Running install.ps1 in Dry-Run mode (basic)..." -ForegroundColor Gray
$dryRunOutput = & $installScript -Mode basic -DryRun -ErrorAction SilentlyContinue *>&1 | Out-String
Assert-True ($dryRunOutput -like "*Fresh Config Installer (Windows)*") "Banner is displayed in dry-run mode"
Assert-True ($dryRunOutput -like "*Warp Terminal*") "Warp Terminal is listed in dry-run mode for basic mode"
Assert-True ($dryRunOutput -like "*Lightshot*") "Lightshot is listed in dry-run mode for basic mode"
Assert-True ($dryRunOutput -like "*Dry-run completed successfully.*") "Dry-run finishes with success message"

# Test 3b: Verify Google Chrome in full mode dry-run
Write-Host "Running install.ps1 in Dry-Run mode (full)..." -ForegroundColor Gray
$dryRunFullOutput = & $installScript -Mode full -DryRun -ErrorAction SilentlyContinue *>&1 | Out-String
Assert-True ($dryRunFullOutput -like "*Google Chrome*") "Google Chrome is listed in dry-run mode for full mode"


# Test 3c: Verify new package IDs and custom installers in dry-run
Assert-True ($dryRunFullOutput -like "*bottom (Clement.bottom)*") "bottom is listed with Clement.bottom"
Assert-True ($dryRunFullOutput -like "*ripgrep (BurntSushi.ripgrep.MSVC)*") "ripgrep is listed with BurntSushi.ripgrep.MSVC"
Assert-True ($dryRunFullOutput -like "*lazygit (JesseDuffield.lazygit)*") "lazygit is listed with JesseDuffield.lazygit"
Assert-True ($dryRunFullOutput -like "*PHP (PHP.PHP.8.4)*") "PHP is listed with PHP.PHP.8.4"
Assert-True ($dryRunFullOutput -like "*Zen Browser (Zen-Team.Zen-Browser)*") "Zen Browser is listed with Zen-Team.Zen-Browser"
Assert-True ($dryRunFullOutput -like "*Podman Desktop (RedHat.Podman-Desktop)*") "Podman Desktop is listed with RedHat.Podman-Desktop"
Assert-True ($dryRunFullOutput -like "*Lightshot (Skillbrains.Lightshot)*") "Lightshot is listed with Skillbrains.Lightshot"


# Test 4: Logs generation
$logDir = Join-Path $PSScriptRoot "..\logs"
Assert-True (Test-Path $logDir) "logs directory exists"
$logFiles = Get-ChildItem -Path $logDir -Filter "install-*.log"
Assert-True ($logFiles.Count -gt 0) "At least one install log file was created under logs/"

# Final Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor Red

if ($testsFailed -gt 0) {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "All Windows installer tests passed!" -ForegroundColor Green
    exit 0
}
