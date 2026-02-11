# PowerShell script to run UnrealIRCd tests using Docker
# This script runs the test suite against the built server

param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

Write-Host "=== UnrealIRCd Docker Test Script ===" -ForegroundColor Cyan
Write-Host ""

# Check if build output exists
if (-not (Test-Path "build\bin")) {
    Write-Host "ERROR: Build output not found!" -ForegroundColor Red
    Write-Host "Please run build.ps1 first to build the server." -ForegroundColor Yellow
    exit 1
}

# Clean previous test artifacts if requested
if ($Clean) {
    Write-Host "Cleaning previous test artifacts..." -ForegroundColor Yellow
    docker rmi unrealircd-test -f 2>$null
}

# Check if Docker is running
Write-Host "Checking Docker..." -ForegroundColor Yellow
try {
    docker info | Out-Null
} catch {
    Write-Host "ERROR: Docker is not running or not accessible!" -ForegroundColor Red
    exit 1
}

# Build the test Docker image
Write-Host ""
Write-Host "Building test Docker image 'unrealircd-test'..." -ForegroundColor Cyan
docker build -f Dockerfile.test -t unrealircd-test .

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Docker test image build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Test image created successfully!" -ForegroundColor Green

# Run the tests
Write-Host ""
Write-Host "Running test suite..." -ForegroundColor Cyan
Write-Host ""

# Create test logs directory with proper permissions
if (-not (Test-Path "build\logs\test")) {
    New-Item -ItemType Directory -Path "build\logs\test" -Force | Out-Null
}
# Create an empty log file with write permissions
New-Item -ItemType File -Path "build\logs\test\tests.log" -Force | Out-Null

# Build bash command with proper line endings (use LF only)
$bashCmd = "set -e; " +
    "killall -9 unrealircd 2>/dev/null || true; " +
    "mkdir -p ~/unrealircd/conf ~/unrealircd/data ~/unrealircd/logs ~/unrealircd/cache ~/unrealircd/doc ~/unrealircd/tmp ~/unrealircd/lib ~/unrealircd/source/src/modules/third; " +
    "cp -r /build/bin ~/unrealircd/; " +
    "cp -r /build/modules ~/unrealircd/; " +
    "cp -r /build/conf/* ~/unrealircd/conf/ 2>/dev/null || true; " +
    "cp -r /build/lib/* ~/unrealircd/lib/ 2>/dev/null || true; " +
    "echo 'Preparing test framework with Unix line endings...'; " +
    "/usr/local/bin/prepare-tests.sh; " +
    "cd /tmp/unrealircd-tests; " +
    "echo 'Running tests...'; " +
    "./run -services none `$RUNTESTFLAGS 2>&1 | tee /build/logs/test/tests.log || exit 1; " +
    "echo '=== Running database tests ==='; " +
    "./run -services none -boot tests/db/writing/* 2>&1 | tee -a /build/logs/test/tests.log || exit 1; " +
    "./run -services none -keepdbs -boot tests/db/reading/* 2>&1 | tee -a /build/logs/test/tests.log || exit 1; " +
    "echo '=== Running encrypted database tests ==='; " +
    "./run -services none -include db_crypted.conf -boot tests/db/writing/* 2>&1 | tee -a /build/logs/test/tests.log || exit 1; " +
    "./run -services none -include db_crypted.conf -keepdbs -boot tests/db/reading/* 2>&1 | tee -a /build/logs/test/tests.log || exit 1; " +
    "echo '=== Running module tests (chess) ==='; " +
    "./run -services none -boot tests/modules/chess_* 2>&1 | tee -a /build/logs/test/tests.log || exit 1; " +
    "echo ''; " +
    "echo '=== All tests passed! ==='"

# Run the container with proper bash command
# Note: We run as root to handle volume permissions, but switch to unrealircd user for tests
docker run --rm `
    -v "${PWD}\build:/build" `
    -v "${PWD}:/source" `
    -e NOSERVICES=$env:NOSERVICES `
    -e RUNTESTFLAGS=$env:RUNTESTFLAGS `
    unrealircd-test `
    su - unrealircd -c $bashCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Tests failed!" -ForegroundColor Red
    Write-Host "Check build\logs\test\tests.log for details" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "All tests passed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Test logs saved to: build\logs\test\tests.log" -ForegroundColor Cyan
