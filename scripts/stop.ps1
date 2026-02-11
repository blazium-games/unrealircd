# PowerShell script to stop running UnrealIRCd Docker containers

$ErrorActionPreference = "Continue"

Write-Host "=== Stopping UnrealIRCd Docker Containers ===" -ForegroundColor Cyan
Write-Host ""

# Find and stop containers
$containers = docker ps -a --filter "ancestor=unrealircd-build" --format "{{.ID}} {{.Names}}"
$containers += docker ps -a --filter "ancestor=unrealircd-test" --format "{{.ID}} {{.Names}}"

if ($containers) {
    Write-Host "Found containers:" -ForegroundColor Yellow
    $containers | ForEach-Object {
        $parts = $_ -split ' ', 2
        $id = $parts[0]
        $name = $parts[1]
        Write-Host "  $id - $name" -ForegroundColor White
        
        # Stop the container
        docker stop $id 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Stopped" -ForegroundColor Green
        }
        
        # Remove the container
        docker rm $id 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    Removed" -ForegroundColor Green
        }
    }
} else {
    Write-Host "No UnrealIRCd containers found." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
