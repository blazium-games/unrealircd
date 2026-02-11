# PowerShell script to build and test UnrealIRCd
# Combines build.ps1 and test.ps1 into a single workflow

param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

Write-Host "=== UnrealIRCd Build and Test Workflow ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Build
Write-Host "Step 1: Building UnrealIRCd..." -ForegroundColor Yellow
Write-Host ""
& "$PSScriptRoot\build.ps1" -Clean:$Clean

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Build failed! Aborting test run." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=====================" -ForegroundColor Gray
Write-Host ""

# Step 2: Test
Write-Host "Step 2: Running tests..." -ForegroundColor Yellow
Write-Host ""
& "$PSScriptRoot\test.ps1" -Clean:$Clean

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Tests failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=====================" -ForegroundColor Gray
Write-Host ""
Write-Host "=== Build and Test Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Build:  build\bin\" -ForegroundColor White
Write-Host "  Logs:   build\logs\" -ForegroundColor White
Write-Host ""
