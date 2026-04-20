# =============================================================================
# Module 3 - Docker Image Loader for kind
# =============================================================================
#
# Usage:
#   .\load-image.ps1              # Interactive mode
#   .\load-image.ps1 --build      # Build and load
#   .\load-image.ps1 --load       # Load only (if already built)
#   .\load-image.ps1 --all        # Build AND load
#
# Prerequisites:
#   - kind cluster running
#   - BentoML installed (for building)
#   - Docker running
#

$ErrorActionPreference = 'Stop'

$IMAGE_NAME   = "sentiment-api"
$IMAGE_TAG    = "v1"
$FULL_IMAGE   = "${IMAGE_NAME}:${IMAGE_TAG}"
$CLUSTER_NAME = "mlops-workshop"
$MODULE2_PATH = "..\module-2"

function Print-Header  { param($m) Write-Host "`n========================================" -ForegroundColor Blue; Write-Host $m -ForegroundColor Blue; Write-Host "========================================`n" -ForegroundColor Blue }
function Print-Success { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Print-Error   { param($m) Write-Host "ERR $m" -ForegroundColor Red }
function Print-Warning { param($m) Write-Host "WRN $m" -ForegroundColor Yellow }
function Print-Info    { param($m) Write-Host "    $m" -ForegroundColor Cyan }

function Check-ImageExists {
    $images = docker images 2>&1
    return ($images | Select-String "${IMAGE_NAME}.*${IMAGE_TAG}") -ne $null
}

function Check-ImageInKind {
    $images = docker exec "${CLUSTER_NAME}-control-plane" crictl images 2>&1
    return ($images | Select-String $IMAGE_NAME) -ne $null
}

function Check-Prerequisites {
    param([string]$Mode)
    Print-Header "Checking Prerequisites"

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Print-Error "Docker not found. Please install Docker Desktop."; exit 1
    }
    Print-Success "Docker found"

    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Print-Error "Docker daemon is not running."; exit 1 }
    Print-Success "Docker daemon running"

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

    if ($Mode -eq "build") {
        if (-not (Get-Command bentoml -ErrorAction SilentlyContinue)) {
            Print-Error "BentoML not found. Install with: pip install bentoml"; exit 1
        }
        Print-Success "BentoML found"
    }
}

function Build-Image {
    Print-Header "Building Docker Image"

    if (-not (Test-Path $MODULE2_PATH)) {
        Print-Error "Module 2 directory not found: $MODULE2_PATH"; exit 1
    }

    Push-Location $MODULE2_PATH
    try {
        Print-Info "Checking for saved BentoML models..."
        $models = bentoml models list 2>&1
        if (-not ($models | Select-String "sentiment")) {
            Print-Warning "No sentiment model found in BentoML store"
            Print-Info "Run one of the service files first: python step1_basic_service.py"
            exit 1
        }
        Print-Success "BentoML model found"

        Print-Info "Checking for built Bentos..."
        $bentos = bentoml list 2>&1
        if (-not ($bentos | Select-String "sentiment_service")) {
            Print-Warning "No sentiment_service Bento found — building..."
            if (-not (Test-Path "bentofile.yaml")) {
                Print-Error "bentofile.yaml not found in $MODULE2_PATH"; exit 1
            }
            bentoml build
            if ($LASTEXITCODE -ne 0) { Print-Error "Failed to build Bento"; exit 1 }
            Print-Success "Bento built successfully"
        } else {
            Print-Success "Bento found"
        }

        $bentoTag = (bentoml list sentiment_service -o json 2>&1 | ConvertFrom-Json)[0].tag
        if (-not $bentoTag) { $bentoTag = "latest" }
        Print-Info "Using Bento: sentiment_service:$bentoTag"

        Print-Info "Containerizing Bento (this may take a few minutes)..."
        bentoml containerize "sentiment_service:$bentoTag" -t $FULL_IMAGE
        if ($LASTEXITCODE -ne 0) { Print-Error "Failed to build Docker image"; exit 1 }
        Print-Success "Docker image built: $FULL_IMAGE"
    } finally {
        Pop-Location
    }

    Print-Header "Image Details"
    docker images | Select-String -Pattern "REPOSITORY|$IMAGE_NAME"
}

function Load-Image {
    Print-Header "Loading Image into kind Cluster"

    if (-not (Check-ImageExists)) {
        Print-Error "Docker image '$FULL_IMAGE' not found locally."
        Print-Info "Build it first with: .\load-image.ps1 --build"
        exit 1
    }

    Print-Info "Loading $FULL_IMAGE into kind cluster '$CLUSTER_NAME'..."
    kind load docker-image $FULL_IMAGE --name $CLUSTER_NAME
    if ($LASTEXITCODE -ne 0) { Print-Error "Failed to load image into kind"; exit 1 }
    Print-Success "Image loaded successfully"

    Print-Info "Verifying image in kind cluster..."
    if (Check-ImageInKind) {
        Print-Success "Image verified in kind cluster"
        docker exec "${CLUSTER_NAME}-control-plane" crictl images | Select-String -Pattern "IMAGE|$IMAGE_NAME"
    } else {
        Print-Warning "Could not verify image in kind (but load command succeeded)"
    }
}

function Show-Menu {
    Print-Header "Module 3 - Docker Image Loader"
    Write-Host "Current status:`n"

    if (Check-ImageExists) {
        Write-Host "  OK  Docker image exists locally" -ForegroundColor Green
        docker images | Select-String "${IMAGE_NAME}.*${IMAGE_TAG}"
    } else {
        Write-Host "  --  Docker image not found locally" -ForegroundColor Red
    }
    Write-Host ""
    if (Check-ImageInKind) {
        Write-Host "  OK  Image loaded in kind cluster" -ForegroundColor Green
    } else {
        Write-Host "  --  Image not loaded in kind cluster" -ForegroundColor Red
    }

    Write-Host "`nWhat would you like to do?`n"
    Write-Host "  1) Build Docker image (using BentoML)"
    Write-Host "  2) Load image into kind cluster"
    Write-Host "  3) Build AND load (complete workflow)"
    Write-Host "  4) Check status only"
    Write-Host "  5) Exit`n"
    $choice = Read-Host "Enter choice [1-5]"

    switch ($choice) {
        "1" { Check-Prerequisites "build"; Build-Image; Print-Info "Next: .\load-image.ps1 --load" }
        "2" { Check-Prerequisites "load";  Load-Image;  Print-Info "Next: .\deploy.ps1" }
        "3" { Check-Prerequisites "build"; Build-Image; Load-Image; Print-Success "Complete! Next: .\deploy.ps1" }
        "4" { Print-Info "Status check complete" }
        "5" { exit 0 }
        default { Print-Error "Invalid choice"; exit 1 }
    }
}

# Main
$arg = if ($args.Count -gt 0) { $args[0] } else { "" }
switch ($arg) {
    "--build" { Check-Prerequisites "build"; Build-Image; Print-Info "Image built. Run: .\load-image.ps1 --load" }
    "--load"  { Check-Prerequisites "load";  Load-Image }
    "--all"   { Check-Prerequisites "build"; Build-Image; Load-Image; Print-Success "Complete! Next: .\deploy.ps1" }
    ""        { Check-Prerequisites "build"; Show-Menu }
    default   { Print-Error "Invalid argument: $arg"; Print-Info "Usage: .\load-image.ps1 [--build|--load|--all]"; exit 1 }
}
