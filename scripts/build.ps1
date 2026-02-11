# PowerShell script to build UnrealIRCd using Docker
# This script builds the Docker image and runs the build process

param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

Write-Host "=== UnrealIRCd Docker Build Script ===" -ForegroundColor Cyan
Write-Host ""

# Clean previous build if requested
if ($Clean) {
    Write-Host "Cleaning previous build..." -ForegroundColor Yellow
    Remove-Item -Path "build" -Recurse -Force -ErrorAction SilentlyContinue
    docker rmi unrealircd-build -f 2>$null
}

# Create build directories
Write-Host "Creating build directories..." -ForegroundColor Yellow
$buildDirs = @("build", "build\bin", "build\modules", "build\logs")
foreach ($dir in $buildDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Check if Docker is running
Write-Host "Checking Docker..." -ForegroundColor Yellow
try {
    docker info | Out-Null
} catch {
    Write-Host "ERROR: Docker is not running or not accessible!" -ForegroundColor Red
    exit 1
}

# Build the Docker image
Write-Host ""
Write-Host "Building Docker image 'unrealircd-build'..." -ForegroundColor Cyan
Write-Host "Note: First build may take 5-10 minutes to download Ubuntu and dependencies..." -ForegroundColor Yellow
docker build -f Dockerfile.build -t unrealircd-build . --progress=plain

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Docker build failed!" -ForegroundColor Red
    
    # Check for common error messages
    $errorMsg = $Error[0].ToString()
    if ($errorMsg -match "docker-credential") {
        Write-Host ""
        Write-Host "Docker credential issue detected. Try running:" -ForegroundColor Yellow
        Write-Host "  .\docker-scripts\fix-docker-creds.ps1" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Or restart Docker Desktop and try again." -ForegroundColor Yellow
    }
    
    exit 1
}

Write-Host ""
Write-Host "Build image created successfully!" -ForegroundColor Green

# Run the container to copy artifacts
Write-Host ""
Write-Host "Extracting build artifacts..." -ForegroundColor Cyan

# Create a temporary container to copy files
$containerId = docker create unrealircd-build

# Copy the build output
docker cp "${containerId}:/build" "."

# Remove the temporary container
docker rm $containerId | Out-Null

Write-Host ""
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Build output:" -ForegroundColor Cyan
Write-Host "  Binaries:  build\bin\" -ForegroundColor White
Write-Host "  Modules:   build\modules\" -ForegroundColor White
Write-Host "  Logs:      build\logs\" -ForegroundColor White
Write-Host ""
Write-Host "To view build logs: Get-Content build\logs\build.log" -ForegroundColor Yellow
