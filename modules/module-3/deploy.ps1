# =============================================================================
# Module 3 - Kubernetes Deployment Script
# =============================================================================
#
# Usage:
#   .\deploy.ps1          # Interactive mode
#   .\deploy.ps1 step1    # Deploy specific step
#   .\deploy.ps1 step2
#   .\deploy.ps1 step3
#   .\deploy.ps1 step4
#
# Prerequisites:
#   - kind cluster running (kind get clusters)
#   - kubectl configured (kubectl cluster-info)
#   - Docker image built (sentiment-api:v1)
#

$ErrorActionPreference = 'Stop'

function Print-Header  { param($m) Write-Host "`n========================================" -ForegroundColor Blue; Write-Host $m -ForegroundColor Blue; Write-Host "========================================`n" -ForegroundColor Blue }
function Print-Success { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Print-Error   { param($m) Write-Host "ERR $m" -ForegroundColor Red }
function Print-Warning { param($m) Write-Host "WRN $m" -ForegroundColor Yellow }
function Print-Info    { param($m) Write-Host "    $m" -ForegroundColor Cyan }

function Check-Prerequisites {
    param([string]$Step)
    Print-Header "Checking Prerequisites"

    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Print-Error "kubectl not found."; exit 1
    }
    Print-Success "kubectl found"

    if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
        Print-Error "kind not found."; exit 1
    }
    Print-Success "kind found"

    $clusters = kind get clusters 2>&1
    if (-not ($clusters | Select-String "mlops-workshop")) {
        Print-Error "kind cluster 'mlops-workshop' not found."
        Print-Info "Create it with: kind create cluster --name mlops-workshop"
        exit 1
    }
    Print-Success "kind cluster 'mlops-workshop' found"

    kubectl cluster-info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Cannot connect to Kubernetes cluster."
        Print-Info "Switch context: kubectl config use-context kind-mlops-workshop"
        exit 1
    }
    Print-Success "kubectl connected to cluster"

    $images = & { $ErrorActionPreference = 'SilentlyContinue'; docker images }
    if (-not ($images | Select-String "sentiment-api.*v1")) {
        Print-Warning "Docker image 'sentiment-api:v1' not found locally."
        Print-Info "Build it with: cd ..\module-2 && bentoml containerize sentiment_service:latest -t sentiment-api:v1"
        $reply = Read-Host "Continue anyway? (y/n)"
        if ($reply -notmatch '^[Yy]$') { exit 1 }
    } else {
        Print-Success "Docker image 'sentiment-api:v1' found"
    }

    Print-Info "Checking if image is loaded in kind cluster..."
    $kindImages = & { $ErrorActionPreference = 'SilentlyContinue'; docker exec mlops-workshop-control-plane crictl images }
    if (-not ($kindImages | Select-String "sentiment-api")) {
        Print-Warning "Docker image not loaded in kind cluster -- loading now..."
        kind load docker-image sentiment-api:v1 --name mlops-workshop
        if ($LASTEXITCODE -ne 0) { Print-Error "Failed to load image into kind"; exit 1 }
        Print-Success "Image loaded into kind cluster"
    } else {
        Print-Success "Docker image already loaded in kind cluster"
    }

    if ($Step -eq "step4") {
        Print-Info "Checking metrics-server (required for HPA)..."
        kubectl get deployment metrics-server -n kube-system 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Print-Warning "metrics-server not found -- installing..."
            kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
            kubectl patch deployment metrics-server -n kube-system --type='json' `
                -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
            Print-Info "Waiting for metrics-server to be ready..."
            kubectl wait --for=condition=available --timeout=60s deployment/metrics-server -n kube-system
            Print-Success "metrics-server installed and ready"
        } else {
            Print-Success "metrics-server already installed"
        }
    }
}

function Deploy-Step {
    param([string]$Step)
    $stepNum = $Step -replace 'step',''
    $file = Get-ChildItem "step${stepNum}-*.yaml" -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $file) {
        Print-Error "File not found: step${stepNum}-*.yaml"; exit 1
    }

    Print-Header "Deploying ${Step}: $($file.Name)"

    Print-Info "Resources to be created:"
    kubectl apply -f $file.Name --dry-run=client 2>&1 | Select-String "configmap|deployment|service|horizontalpodautoscaler|poddisruptionbudget"

    $reply = Read-Host "Deploy these resources? (y/n)"
    if ($reply -notmatch '^[Yy]$') { Print-Warning "Deployment cancelled"; exit 0 }

    Print-Info "Deploying..."
    kubectl apply -f $file.Name
    if ($LASTEXITCODE -ne 0) { Print-Error "Failed to apply resources"; exit 1 }
    Print-Success "Resources applied successfully"

    Print-Info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/sentiment-api
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Deployment failed to become ready"
        Print-Info "Check status: kubectl get pods -l app=sentiment-api"
        Print-Info "Check logs:   kubectl logs -l app=sentiment-api"
        exit 1
    }
    Print-Success "Deployment is ready"

    Print-Header "Deployment Status"
    kubectl get all -l app=sentiment-api

    switch ($Step) {
        "step1" {
            Print-Header "Step 1: Basic Deployment"
            Print-Info "Deployment with 2 replicas + NodePort Service on port 30080"
            Print-Info "Missing: resource limits, health checks, ConfigMap, auto-scaling"
        }
        "step2" {
            Print-Header "Step 2: Resource Management"
            Print-Info "CPU requests: 500m / limits: 1000m"
            Print-Info "Memory requests: 1Gi / limits: 2Gi  |  QoS: Burstable"
            Print-Info "Check resource usage: kubectl top pod -l app=sentiment-api"
        }
        "step3" {
            Print-Header "Step 3: Health Checks & ConfigMap"
            Print-Info "Startup, liveness, and readiness probes added"
            Print-Info "ConfigMap externalises environment variables"
            Print-Info "Check probes: kubectl describe pod <pod-name>"
        }
        "step4" {
            Print-Header "Step 4: Production-Ready Deployment"
            Print-Info "HPA (2-10 replicas), PDB, security context, pod anti-affinity"
            Print-Info "Check HPA: kubectl get hpa sentiment-api-hpa"
            Print-Info "Check PDB: kubectl get pdb sentiment-api-pdb"
        }
    }

    Print-Header "Testing the Deployment"
    Print-Info "Forward the port:"
    Print-Info "  kubectl port-forward svc/sentiment-api-service 8080:80"
    Print-Info ""
    Print-Info "Test the API:"
    Print-Info "  curl -X POST http://localhost:8080/predict -H 'Content-Type: application/json' -d '{`"text`": `"Kubernetes is amazing!`"}'"
    Print-Info ""
    Print-Info "Check logs:"
    Print-Info "  kubectl logs -l app=sentiment-api --tail=50 -f"
}

function Show-Menu {
    Print-Header "Module 3 - Kubernetes Deployment"
    Write-Host "Select which step to deploy:`n"
    Write-Host "  1) Step 1 - Basic Deployment (2 replicas + Service)"
    Write-Host "  2) Step 2 - Add Resource Limits"
    Write-Host "  3) Step 3 - Add Health Probes & ConfigMap"
    Write-Host "  4) Step 4 - Production-Ready (HPA + PDB + Security)"
    Write-Host "  5) Exit`n"
    $choice = Read-Host "Enter choice [1-5]"

    switch ($choice) {
        "1" { Check-Prerequisites "step1"; Deploy-Step "step1" }
        "2" { Check-Prerequisites "step2"; Deploy-Step "step2" }
        "3" { Check-Prerequisites "step3"; Deploy-Step "step3" }
        "4" { Check-Prerequisites "step4"; Deploy-Step "step4" }
        "5" { exit 0 }
        default { Print-Error "Invalid choice"; exit 1 }
    }
}

# Main
$arg = if ($args.Count -gt 0) { $args[0] } else { "" }
if ($arg -eq "") {
    Show-Menu
} elseif ($arg -match '^step[1-4]$') {
    Check-Prerequisites $arg
    Deploy-Step $arg
} else {
    Print-Error "Invalid argument: $arg"
    Print-Info "Usage: .\deploy.ps1 [step1|step2|step3|step4]"
    exit 1
}
