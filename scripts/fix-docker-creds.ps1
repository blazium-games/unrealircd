# PowerShell script to fix Docker credential issues

Write-Host "=== Fixing Docker Credentials ===" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is running
try {
    docker info | Out-Null
} catch {
    Write-Host "ERROR: Docker is not running!" -ForegroundColor Red
    Write-Host "Please start Docker Desktop first." -ForegroundColor Yellow
    exit 1
}

Write-Host "Docker is running." -ForegroundColor Green
Write-Host ""

# Try to login to Docker Hub to refresh credentials
Write-Host "Attempting to refresh Docker credentials..." -ForegroundColor Yellow
Write-Host "If you don't have a Docker Hub account, press Ctrl+C and continue as guest." -ForegroundColor Gray
Write-Host ""

$login = Read-Host "Do you want to login to Docker Hub? (y/n)"
if ($login -eq "y" -or $login -eq "Y") {
    docker login
}

Write-Host ""
Write-Host "If the issue persists, try:" -ForegroundColor Yellow
Write-Host "1. Restart Docker Desktop" -ForegroundColor White
Write-Host "2. Go to Docker Desktop Settings > Resources > Advanced" -ForegroundColor White
Write-Host "3. Click 'Reset to factory defaults'" -ForegroundColor White
Write-Host ""
Write-Host "Then run the build script again:" -ForegroundColor Yellow
Write-Host "  .\docker-scripts\build.ps1" -ForegroundColor Cyan
