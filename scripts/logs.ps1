# PowerShell script to view UnrealIRCd build and test logs

param(
    [string]$Type = "all",
    [int]$Lines = 50
)

$ErrorActionPreference = "Stop"

Write-Host "=== UnrealIRCd Log Viewer ===" -ForegroundColor Cyan
Write-Host ""

# Check if build directory exists
if (-not (Test-Path "build\logs")) {
    Write-Host "ERROR: No logs found. Run build.ps1 first." -ForegroundColor Red
    exit 1
}

# Determine which log to show
switch ($Type.ToLower()) {
    "build" {
        $logPath = "build\logs\build.log"
        $logName = "Build Log"
    }
    "test" {
        $logPath = "build\logs\test\tests.log"
        $logName = "Test Log"
    }
    "config" {
        $logPath = "build\logs\config-error.log"
        $logName = "Config Error Log"
    }
    "all" {
        Write-Host "Showing last $Lines lines of all logs:" -ForegroundColor Yellow
        Write-Host ""
        
        if (Test-Path "build\logs\build.log") {
            Write-Host "=== BUILD LOG ===" -ForegroundColor Cyan
            Get-Content "build\logs\build.log" -Tail $Lines
            Write-Host ""
        }
        
        if (Test-Path "build\logs\test\tests.log") {
            Write-Host "=== TEST LOG ===" -ForegroundColor Cyan
            Get-Content "build\logs\test\tests.log" -Tail $Lines
            Write-Host ""
        }
        
        if (Test-Path "build\logs\config-error.log") {
            Write-Host "=== CONFIG ERROR LOG ===" -ForegroundColor Cyan
            Get-Content "build\logs\config-error.log" -Tail $Lines
            Write-Host ""
        }
        
        exit 0
    }
    default {
        Write-Host "ERROR: Invalid log type '$Type'" -ForegroundColor Red
        Write-Host "Valid types: build, test, config, all" -ForegroundColor Yellow
        exit 1
    }
}

# Show the specific log
if (Test-Path $logPath) {
    Write-Host "Showing last $Lines lines of $logName:" -ForegroundColor Yellow
    Write-Host ""
    Get-Content $logPath -Tail $Lines
} else {
    Write-Host "ERROR: Log file not found: $logPath" -ForegroundColor Red
    exit 1
}
