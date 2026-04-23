#Requires -Version 5.1

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Verifying Kubeflow Pipelines Installation" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] kubectl not found" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] kubectl installed" -ForegroundColor Green

$existingClusters = kind get clusters 2>$null
if ($existingClusters -notcontains "mlops-workshop") {
    Write-Host "[FAIL] kind cluster 'mlops-workshop' not found" -ForegroundColor Red
    Write-Host "  Run: kind create cluster --name mlops-workshop"
    exit 1
}
Write-Host "[OK] kind cluster 'mlops-workshop' exists" -ForegroundColor Green

kubectl get namespace kubeflow 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] kubeflow namespace not found" -ForegroundColor Red
    Write-Host "  Run: .\scripts\install-kubeflow.ps1"
    exit 1
}
Write-Host "[OK] kubeflow namespace exists" -ForegroundColor Green

Write-Host ""
Write-Host "Checking pod status..." -ForegroundColor Yellow
Write-Host ""

$podLines = kubectl get pods -n kubeflow --no-headers 2>$null
$totalPods = ($podLines | Where-Object { $_ -ne "" }).Count
$runningPods = ($podLines | Where-Object { $_ -match "Running" }).Count
$readyPods = ($podLines | Where-Object { $_ -match "\b(1/1|2/2)\b" }).Count

Write-Host "Total pods:   $totalPods"
Write-Host "Running pods: $runningPods"
Write-Host "Ready pods:   $readyPods"
Write-Host ""

kubectl get pods -n kubeflow

Write-Host ""

$podsOk = $false
if ($totalPods -gt 0 -and $runningPods -eq $totalPods -and $readyPods -eq $totalPods) {
    Write-Host "[OK] All pods are Running and Ready" -ForegroundColor Green
    $podsOk = $true
} else {
    Write-Host "[WARN] Some pods are not ready yet" -ForegroundColor Yellow
    Write-Host "  This is normal during first installation."
    Write-Host "  Wait a few more minutes and run this script again."
}

Write-Host ""
Write-Host "Checking services..." -ForegroundColor Yellow
kubectl get svc -n kubeflow ml-pipeline-ui 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] ml-pipeline-ui service exists" -ForegroundColor Green
} else {
    Write-Host "[FAIL] ml-pipeline-ui service not found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Checking UI access..." -ForegroundColor Yellow
$portInUse = Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Host "[OK] Port 8080 is in use (port-forward may be running)" -ForegroundColor Green
    Write-Host "  Access UI at: http://localhost:8080"
} else {
    Write-Host "[WARN] Port 8080 not in use" -ForegroundColor Yellow
    Write-Host "  To access UI, run in a separate terminal:"
    Write-Host "  kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80"
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
if ($podsOk) {
    Write-Host "[OK] Installation Verified Successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Start port-forward (if not already running):"
    Write-Host "   kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8080:80"
    Write-Host ""
    Write-Host "2. Open browser: http://localhost:8080"
    Write-Host ""
    Write-Host "3. Start working on exercises in starter/ directory"
} else {
    Write-Host "[WARN] Installation Incomplete" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Wait a few more minutes for pods to become ready, then run:"
    Write-Host "  .\scripts\verify-installation.ps1"
    Write-Host ""
    Write-Host "Or watch pod status:"
    Write-Host "  kubectl get pods -n kubeflow -w"
}
Write-Host "==================================================" -ForegroundColor Cyan
