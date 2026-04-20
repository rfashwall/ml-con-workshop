# =============================================================================
# Module 4 - Build Script for API Gateway
# =============================================================================
#
# Usage:
#   .\build.ps1                # Interactive mode
#   .\build.ps1 --local        # Build local binary
#   .\build.ps1 --docker       # Build Docker image
#   .\build.ps1 --kind         # Build and load into kind
#   .\build.ps1 --all          # Build everything
#   .\build.ps1 --test         # Test build (no output)
#   .\build.ps1 --deps         # Download dependencies only
#

$ErrorActionPreference = 'Stop'

$IMAGE_NAME   = "api-gateway"
$IMAGE_TAG    = "v1"
$FULL_IMAGE   = "${IMAGE_NAME}:${IMAGE_TAG}"
$CLUSTER_NAME = "mlops-workshop"

function Print-Header  { param($m) Write-Host "`n========================================" -ForegroundColor Blue; Write-Host $m -ForegroundColor Blue; Write-Host "========================================`n" -ForegroundColor Blue }
function Print-Success { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Print-Error   { param($m) Write-Host "ERR $m" -ForegroundColor Red }
function Print-Warning { param($m) Write-Host "WRN $m" -ForegroundColor Yellow }
function Print-Info    { param($m) Write-Host "    $m" -ForegroundColor Cyan }

function Check-Prerequisites {
    param([string]$Mode)
    Print-Header "Checking Prerequisites"

    if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
        Print-Error "Go not found. Install Go 1.21 or later."; exit 1
    }
    $goVer = (go version 2>&1)
    Print-Success "Go found: $goVer"

    if ($Mode -in @("docker","kind","all")) {
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Print-Error "Docker not found."; exit 1
        }
        Print-Success "Docker found"
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Print-Error "Docker daemon not running."; exit 1 }
        Print-Success "Docker daemon running"
    }

    if ($Mode -in @("kind","all")) {
        if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
            Print-Error "kind not found."; exit 1
        }
        Print-Success "kind found"
        $clusters = kind get clusters 2>&1
        if (-not ($clusters | Select-String "^$CLUSTER_NAME$")) {
            Print-Error "kind cluster '$CLUSTER_NAME' not found."
            Print-Info "Create it with: kind create cluster --name $CLUSTER_NAME"
            exit 1
        }
        Print-Success "kind cluster '$CLUSTER_NAME' found"
    }
}

function Download-Deps {
    Print-Header "Downloading Go Dependencies"

    if (-not (Test-Path "go.mod")) {
        Print-Error "go.mod not found. Are you in the module-4 directory?"; exit 1
    }

    Print-Info "Running go mod download..."
    go mod download
    if ($LASTEXITCODE -ne 0) { Print-Error "Failed to download dependencies"; exit 1 }
    Print-Success "Dependencies downloaded"

    Print-Info "Verifying dependencies..."
    go mod verify
    if ($LASTEXITCODE -ne 0) { Print-Warning "Dependency verification failed (may be OK)" }
    else { Print-Success "Dependencies verified" }
}

function Build-Local {
    Print-Header "Building Local Binary"

    Print-Info "Building gateway binary..."
    go build -o gateway.exe starter\gateway.go
    if ($LASTEXITCODE -ne 0) { Print-Error "Build failed"; exit 1 }

    $size = [math]::Round((Get-Item "gateway.exe").Length / 1KB, 1)
    Print-Success "Binary built: .\gateway.exe  (${size} KB)"
    Print-Info ""
    Print-Info "Run locally with:"
    Print-Info "  `$env:BACKEND_URL = 'http://localhost:3000'"
    Print-Info "  `$env:LOG_LEVEL   = 'debug'"
    Print-Info "  .\gateway.exe"
}

function Build-Docker {
    Print-Header "Building Docker Image"

    Print-Info "Building $FULL_IMAGE (this may take a few minutes on first build)..."
    $start = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    docker build -t $FULL_IMAGE .
    if ($LASTEXITCODE -ne 0) { Print-Error "Docker build failed"; exit 1 }

    $duration = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $start
    Print-Success "Docker image built in ${duration}s"

    Print-Header "Image Information"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}" | Select-String -Pattern "REPOSITORY|$IMAGE_NAME"

    Print-Info ""
    Print-Info "Run container with:"
    Print-Info "  docker run -p 8080:8080 -e BACKEND_URL=http://host.docker.internal:3000 -e LOG_LEVEL=debug $FULL_IMAGE"
}

function Load-Kind {
    Print-Header "Loading Image into kind Cluster"

    $images = docker images --format "{{.Repository}}:{{.Tag}}"
    if (-not ($images | Select-String "^${IMAGE_NAME}:${IMAGE_TAG}$")) {
        Print-Error "Docker image '$FULL_IMAGE' not found. Build it first: .\build.ps1 --docker"
        exit 1
    }

    Print-Info "Loading $FULL_IMAGE into kind cluster '$CLUSTER_NAME'..."
    kind load docker-image $FULL_IMAGE --name $CLUSTER_NAME
    if ($LASTEXITCODE -ne 0) { Print-Error "Failed to load image into kind"; exit 1 }
    Print-Success "Image loaded into kind"

    Print-Info "Verifying image in kind..."
    $kindImages = docker exec "${CLUSTER_NAME}-control-plane" crictl images 2>&1
    if ($kindImages | Select-String $IMAGE_NAME) {
        Print-Success "Image verified in kind"
    } else {
        Print-Warning "Could not verify (but load succeeded)"
    }
}

function Test-Build {
    Print-Header "Testing Build"

    Print-Info "Running go build (null output)..."
    go build -o NUL starter\gateway.go
    if ($LASTEXITCODE -ne 0) { Print-Error "Build test failed"; exit 1 }
    Print-Success "Build test passed"
}

function Run-Tests {
    Print-Header "Running Tests"

    $testFiles = Get-ChildItem "*_test.go" -ErrorAction SilentlyContinue
    if ($testFiles) {
        Print-Info "Running go test..."
        go test -v ./...
        if ($LASTEXITCODE -ne 0) { Print-Error "Tests failed"; exit 1 }
        Print-Success "Tests passed"
    } else {
        Print-Warning "No test files found"
        Print-Info "You should add tests! Example: gateway_test.go"
    }
}

function Show-Menu {
    Print-Header "Module 4 - API Gateway Builder"
    Write-Host "Select build option:`n"
    Write-Host "  1) Download dependencies only"
    Write-Host "  2) Build local binary (for testing)"
    Write-Host "  3) Build Docker image"
    Write-Host "  4) Load Docker image into kind"
    Write-Host "  5) Build everything (binary + Docker + kind)"
    Write-Host "  6) Test build (no output)"
    Write-Host "  7) Run tests"
    Write-Host "  8) Exit`n"
    $choice = Read-Host "Enter choice [1-8]"

    switch ($choice) {
        "1" { Check-Prerequisites "local";  Download-Deps }
        "2" { Check-Prerequisites "local";  Download-Deps; Build-Local }
        "3" { Check-Prerequisites "docker"; Build-Docker }
        "4" { Check-Prerequisites "kind";   Load-Kind }
        "5" {
            Check-Prerequisites "all"
            Download-Deps; Build-Local; Build-Docker; Load-Kind
            Print-Success "All builds complete!"
            Print-Info "Next: kubectl apply -f deployment.yaml"
        }
        "6" { Check-Prerequisites "local"; Test-Build }
        "7" { Check-Prerequisites "local"; Download-Deps; Run-Tests }
        "8" { exit 0 }
        default { Print-Error "Invalid choice"; exit 1 }
    }
}

# Main
$arg = if ($args.Count -gt 0) { $args[0] } else { "" }
switch ($arg) {
    "--local"  { Check-Prerequisites "local";  Download-Deps; Build-Local }
    "--docker" { Check-Prerequisites "docker"; Build-Docker }
    "--kind"   { Check-Prerequisites "kind";   Load-Kind }
    "--all"    { Check-Prerequisites "all";    Download-Deps; Build-Local; Build-Docker; Load-Kind; Print-Success "All builds complete!" }
    "--test"   { Check-Prerequisites "local";  Test-Build }
    "--deps"   { Check-Prerequisites "local";  Download-Deps }
    ""         { Show-Menu }
    default    { Print-Error "Invalid argument: $arg"; Print-Info "Usage: .\build.ps1 [--local|--docker|--kind|--all|--test|--deps]"; exit 1 }
}
