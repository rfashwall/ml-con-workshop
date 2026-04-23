#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Installing Kubeflow Pipelines on kind cluster" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$CLUSTER_NAME = "mlops-workshop"
$PIPELINE_VERSION = "2.14.3"

Write-Host "Step 1: Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "Error: kubectl not found" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] kubectl found" -ForegroundColor Green

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "Error: kind not found" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] kind found" -ForegroundColor Green

$existingClusters = kind get clusters 2>$null
if ($existingClusters -notcontains $CLUSTER_NAME) {
    Write-Host "kind cluster '$CLUSTER_NAME' not found. Creating it..." -ForegroundColor Yellow
    kind create cluster --name $CLUSTER_NAME
    Write-Host "[OK] kind cluster created" -ForegroundColor Green
} else {
    Write-Host "[OK] kind cluster '$CLUSTER_NAME' found" -ForegroundColor Green
}
Write-Host ""

Write-Host "Step 2: Installing Kubeflow Pipelines (Standalone)" -ForegroundColor Yellow
Write-Host "Version: $PIPELINE_VERSION"
Write-Host "This may take several minutes..."
Write-Host ""

Write-Host "Installing cluster-scoped resources..." -ForegroundColor Yellow
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$PIPELINE_VERSION"
kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io

Write-Host "Installing cert-manager resources..." -ForegroundColor Yellow
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

Write-Host "Installing Kubeflow Pipelines components..." -ForegroundColor Yellow
kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/cert-manager/platform-agnostic-k8s-native?ref=$PIPELINE_VERSION"

Write-Host "[OK] Kubeflow Pipelines manifests applied" -ForegroundColor Green
Write-Host ""

Write-Host "Step 3: Waiting for pods to start..." -ForegroundColor Yellow
Write-Host "This may take 3-5 minutes for images to download and pods to start..."
Write-Host ""

Write-Host "Waiting for kubeflow namespace..." -ForegroundColor Yellow
$nsReady = $false
for ($i = 1; $i -le 30; $i++) {
    $ns = kubectl get namespace kubeflow 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] kubeflow namespace ready" -ForegroundColor Green
        $nsReady = $true
        break
    }
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Patching minio deployment with compatible image..." -ForegroundColor Yellow
for ($i = 1; $i -le 30; $i++) {
    kubectl get deployment minio -n kubeflow 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        kubectl set image deployment/minio -n kubeflow minio=minio/minio:RELEASE.2025-09-07T16-13-09Z-cpuv1
        Write-Host "[OK] minio deployment patched" -ForegroundColor Green
        break
    }
    Write-Host "Waiting for minio deployment to be created..."
    Start-Sleep -Seconds 2
}

Start-Sleep -Seconds 10

Write-Host ""
Write-Host "Current pod status in kubeflow namespace:" -ForegroundColor Yellow
kubectl get pods -n kubeflow
Write-Host ""

Write-Host "Waiting for pods to become ready (this may take a few minutes)..." -ForegroundColor Yellow
Write-Host "You can press Ctrl+C and run this manually later:"
Write-Host "  kubectl wait --for=condition=Ready --timeout=300s -n kubeflow pod --all"
Write-Host ""

kubectl wait --for=condition=Ready --timeout=600s -n kubeflow pod --all 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] Some pods are not ready yet. This is normal for first-time installation." -ForegroundColor Yellow
    Write-Host "  Check status with: kubectl get pods -n kubeflow" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host ""
Write-Host "1. Check pod status (wait until all pods are Running):"
Write-Host "   kubectl get pods -n kubeflow"
Write-Host ""
Write-Host "2. Watch pods until all are ready (Ctrl+C to exit):"
Write-Host "   kubectl get pods -n kubeflow -w"
Write-Host ""
Write-Host "3. Once ready, port-forward to access UI:"
Write-Host "   kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80"
Write-Host ""
Write-Host "4. Open browser:"
Write-Host "   http://localhost:8080"
Write-Host ""
Write-Host "Note: First-time installation downloads large images." -ForegroundColor Yellow
Write-Host "It may take 5-10 minutes for all pods to be ready." -ForegroundColor Yellow
Write-Host ""
