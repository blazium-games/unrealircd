# PowerShell script to watch GitHub Actions workflow runs
# Uses gh CLI to monitor runs, detect success/failure, download logs on failure,
# and output JSON or verbose debug logging

param(
    [Parameter(Mandatory = $false)]
    [string]$Repo = "",
    [Parameter(Mandatory = $false)]
    [string]$RunId = "",
    [Parameter(Mandatory = $false)]
    [string]$Workflow = "",
    [Parameter(Mandatory = $false)]
    [string]$Branch = "",
    [Parameter(Mandatory = $false)]
    [string]$Commit = "",
    [Parameter(Mandatory = $false)]
    [string]$LogDir = "build\logs\gh",
    [switch]$Json,
    [switch]$Trigger
)

$ErrorActionPreference = "Stop"

function Write-DebugLog {
    param([string]$Message, [string]$Color = "White")
    if (-not $Json) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] $Message" -ForegroundColor $Color
    }
}

function Get-RepoFromGitRemote {
    try {
        $remoteUrl = git remote get-url origin 2>$null
        if (-not $remoteUrl) { return $null }
        if ($remoteUrl -match "github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$") {
            return "$($Matches[1])/$($Matches[2])"
        }
        if ($remoteUrl -match "([^/]+)/([^/.]+)(?:\.git)?$") {
            return "$($Matches[1])/$($Matches[2])"
        }
        return $null
    } catch {
        return $null
    }
}

function Get-GhRunId {
    param([string]$GhRepo, [string]$WorkflowName, [string]$BranchFilter, [string]$CommitSha)
    $ghArgs = @("run", "list", "--limit", "1", "--json", "databaseId,workflowName")
    if ($GhRepo) { $ghArgs += @("-R", $GhRepo) }
    if ($WorkflowName) { $ghArgs += @("--workflow", $WorkflowName) }
    if ($BranchFilter) { $ghArgs += @("--branch", $BranchFilter) }
    if ($CommitSha) { $ghArgs += @("--commit", $CommitSha) }
    $result = gh @ghArgs 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $json = $result | ConvertFrom-Json
    if ($json -and $json.PSObject.Properties.Count -gt 0) {
        return $json[0].databaseId.ToString()
    }
    return $null
}

# --- Main ---

if (-not $Json) {
    Write-Host "=== GitHub Workflow Watcher ===" -ForegroundColor Cyan
    Write-Host ""
}

# Check gh CLI
Write-DebugLog "Checking gh CLI..." "Yellow"
$ghPath = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghPath) {
    Write-DebugLog "ERROR: gh CLI not found. Install from https://cli.github.com/" "Red"
    if ($Json) {
        Write-Output '{"success":false,"error":"gh CLI not found"}'
    }
    exit 1
}

# Auth check
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-DebugLog "ERROR: gh not authenticated. Run 'gh auth login'" "Red"
    if ($Json) {
        Write-Output '{"success":false,"error":"gh not authenticated"}'
    }
    exit 1
}
Write-DebugLog "gh CLI OK" "Green"

# Resolve repo
$effectiveRepo = $Repo
if (-not $effectiveRepo) {
    Write-DebugLog "Repo not set, resolving from git remote..." "Yellow"
    $effectiveRepo = Get-RepoFromGitRemote
    if (-not $effectiveRepo) {
        Write-DebugLog "ERROR: Could not resolve repo. Use -Repo owner/repo" "Red"
        if ($Json) {
            Write-Output '{"success":false,"error":"Could not resolve repo"}'
        }
        exit 1
    }
    Write-DebugLog "Resolved repo: $effectiveRepo" "Green"
} else {
    Write-DebugLog "Using repo: $effectiveRepo" "Green"
}

$repoArg = @("-R", $effectiveRepo)

# Resolve run ID
$effectiveRunId = $RunId
if (-not $effectiveRunId) {
    Write-DebugLog "RunId not set, fetching latest run..." "Yellow"
    if (-not $Workflow) {
        Write-DebugLog "ERROR: -Workflow required when -RunId not provided" "Red"
        if ($Json) {
            Write-Output '{"success":false,"error":"Workflow required when RunId not provided"}'
        }
        exit 1
    }
    $effectiveRunId = Get-GhRunId -GhRepo $effectiveRepo -WorkflowName $Workflow -BranchFilter $Branch -CommitSha $Commit
    if (-not $effectiveRunId) {
        Write-DebugLog "ERROR: No runs found for workflow '$Workflow'" "Red"
        if ($Json) {
            Write-Output '{"success":false,"error":"No runs found"}'
        }
        exit 1
    }
    Write-DebugLog "Latest run ID: $effectiveRunId" "Green"
} else {
    Write-DebugLog "Using run ID: $effectiveRunId" "Green"
}

# Optional: trigger workflow first
if ($Trigger -and $Workflow) {
    Write-DebugLog "Triggering workflow: $Workflow..." "Yellow"
    $triggerArgs = @("workflow", "run", $Workflow) + $repoArg
    if ($Branch) { $triggerArgs += @("--ref", $Branch) }
    gh @triggerArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-DebugLog "ERROR: Failed to trigger workflow" "Red"
        if ($Json) {
            Write-Output '{"success":false,"error":"Failed to trigger workflow"}'
        }
        exit 1
    }
    Write-DebugLog "Workflow triggered, waiting 5s before fetching run..." "Yellow"
    Start-Sleep -Seconds 5
    $effectiveRunId = Get-GhRunId -GhRepo $effectiveRepo -WorkflowName $Workflow -BranchFilter $Branch -CommitSha $Commit
    if (-not $effectiveRunId) {
        Write-DebugLog "ERROR: Could not find triggered run" "Red"
        if ($Json) {
            Write-Output '{"success":false,"error":"Could not find triggered run"}'
        }
        exit 1
    }
    Write-DebugLog "Watching triggered run: $effectiveRunId" "Green"
}

# Watch the run
Write-DebugLog "Watching run $effectiveRunId until completion..." "Cyan"
gh run watch $effectiveRunId @repoArg --exit-status 2>&1 | Out-Null
$watchExit = $LASTEXITCODE
Write-DebugLog "Run completed (watch exit: $watchExit)" "Green"

# Get run details
$viewJson = gh run view $effectiveRunId @repoArg --json conclusion,status,name,url 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-DebugLog "ERROR: Failed to get run details" "Red"
    if ($Json) {
        Write-Output ('{"success":false,"error":"Failed to get run details","runId":"' + $effectiveRunId + '"}')
    }
    exit 1
}

$runInfo = $viewJson | ConvertFrom-Json
$conclusion = $runInfo.conclusion
$status = $runInfo.status
$workflowName = $runInfo.name
$url = $runInfo.url

$isSuccess = $conclusion -eq "success"

# On failure: download logs
$logPath = $null
if (-not $isSuccess) {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $logPath = Join-Path $LogDir "run-$effectiveRunId-failed.log"
    Write-DebugLog "Run failed. Saving failed steps log to: $logPath" "Yellow"
    gh run view $effectiveRunId @repoArg --log-failed 2>&1 | Out-File -FilePath $logPath -Encoding utf8
    Write-DebugLog "Log saved" "Green"
}

# Build output
$result = @{
    success      = $isSuccess
    conclusion   = $conclusion
    status       = $status
    runId        = $effectiveRunId
    workflowName = $workflowName
    url          = $url
}
if ($logPath) {
    $absPath = $logPath
    try {
        $absPath = (Resolve-Path $logPath -ErrorAction Stop).Path
    } catch { }
    $result["logPath"] = $absPath
}

if ($Json) {
    $result | ConvertTo-Json -Compress
} else {
    Write-Host ""
    if ($isSuccess) {
        Write-Host "SUCCESS: Workflow completed successfully" -ForegroundColor Green
        Write-Host "  Run: $url" -ForegroundColor Cyan
    } else {
        Write-Host "FAILURE: Workflow did not succeed (conclusion: $conclusion)" -ForegroundColor Red
        Write-Host "  Run: $url" -ForegroundColor Cyan
        Write-Host "  Log: $($result.logPath)" -ForegroundColor Yellow
    }
}

exit $(if ($isSuccess) { 0 } else { 1 })
