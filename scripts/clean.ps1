# PowerShell script to clean Docker images, containers, and build output

$ErrorActionPreference = "Stop"

Write-Host "=== UnrealIRCd Docker Clean Script ===" -ForegroundColor Cyan
Write-Host ""

# Stop any running containers
Write-Host "Stopping containers..." -ForegroundColor Yellow
docker ps -a --filter "ancestor=unrealircd-build" --format "{{.ID}}" | ForEach-Object {
    docker stop $_ 2>$null
    docker rm $_ 2>$null
}
docker ps -a --filter "ancestor=unrealircd-test" --format "{{.ID}}" | ForEach-Object {
    docker stop $_ 2>$null
    docker rm $_ 2>$null
}

# Remove Docker images
Write-Host "Removing Docker images..." -ForegroundColor Yellow
docker rmi unrealircd-build 2>$null
docker rmi unrealircd-test 2>$null

# Remove build output
Write-Host "Removing build output..." -ForegroundColor Yellow
if (Test-Path "build") {
    Remove-Item -Path "build" -Recurse -Force
    Write-Host "Build directory removed." -ForegroundColor Green
} else {
    Write-Host "No build directory found." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Cleanup complete!" -ForegroundColor Green
