# =============================================================================
# Module 4 - Deploy Script for API Gateway
# =============================================================================
#
# Usage:
#   .\deploy.ps1           # Interactive mode
#   .\deploy.ps1 --deploy  # Deploy gateway
#   .\deploy.ps1 --test    # Test deployment
#   .\deploy.ps1 --clean   # Remove deployment
#

$ErrorActionPreference = 'Stop'

function Print-Header  { param($m) Write-Host "`n========================================" -ForegroundColor Blue; Write-Host $m -ForegroundColor Blue; Write-Host "========================================`n" -ForegroundColor Blue }
function Print-Success { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Print-Error   { param($m) Write-Host "ERR $m" -ForegroundColor Red }
function Print-Warning { param($m) Write-Host "WRN $m" -ForegroundColor Yellow }
function Print-Info    { param($m) Write-Host "    $m" -ForegroundColor Cyan }

function Check-Prerequisites {
    Print-Header "Checking Prerequisites"

    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Print-Error "kubectl not found"; exit 1
    }
    Print-Success "kubectl found"

    kubectl cluster-info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Print-Error "Cannot connect to Kubernetes cluster"; exit 1 }
    Print-Success "Connected to cluster"

    kubectl get svc sentiment-api-service 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Print-Warning "ML service (sentiment-api-service) not found"
        Print-Info "Deploy Module 3 first: cd ..\module-3 && .\deploy.ps1"
        $reply = Read-Host "Continue anyway? (y/n)"
        if ($reply -notmatch '^[Yy]$') { exit 1 }
    } else {
        Print-Success "ML service found"
    }
}

function Deploy-Gateway {
    Print-Header "Deploying API Gateway"

    Print-Info "Applying Kubernetes manifests..."
    kubectl apply -f deployment.yaml
    if ($LASTEXITCODE -ne 0) { Print-Error "Failed to apply manifests"; exit 1 }
    Print-Success "Manifests applied"

    Print-Info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/api-gateway
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Deployment failed to become ready"
        Print-Info "Check with: kubectl get pods -l app=api-gateway"
        exit 1
    }
    Print-Success "Deployment ready"

    Print-Header "Deployment Status"
    kubectl get all -l app=api-gateway
}

function Test-Deployment {
    Print-Header "Testing API Gateway"

    kubectl get deployment api-gateway 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Gateway not deployed. Deploy first: .\deploy.ps1 --deploy"
        exit 1
    }

    Print-Info "Setting up port-forward on port 8080..."
    $pf = Start-Process -FilePath "kubectl" -ArgumentList "port-forward","svc/api-gateway-service","8080:80" -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 3

    try {
        Print-Info "Testing /health endpoint..."
        $health = Invoke-WebRequest -Uri "http://localhost:8080/health" -UseBasicParsing -ErrorAction Stop
        Print-Success "Health check passed"
        $health.Content | ConvertFrom-Json | ConvertTo-Json

        Print-Info "Testing /predict endpoint..."
        $body = '{"request": {"text": "Production ready!","request_id": null}}'
        $resp = Invoke-WebRequest -Uri "http://localhost:8080/predict" -Method POST `
            -ContentType "application/json" -Body $body -UseBasicParsing -ErrorAction Stop
        Print-Success "Prediction successful"
        $resp.Content | ConvertFrom-Json | ConvertTo-Json

        Print-Success "All tests passed!"
    } catch {
        Print-Error "Test failed: $_"
    } finally {
        Stop-Process -Id $pf.Id -ErrorAction SilentlyContinue
    }
}

function Invoke-Cleanup {
    Print-Header "Cleaning Up"
    Print-Warning "This will DELETE the API gateway deployment"
    $reply = Read-Host "Continue? (y/n)"
    if ($reply -notmatch '^[Yy]$') { Print-Info "Cancelled"; exit 0 }

    Print-Info "Deleting resources..."
    kubectl delete -f deployment.yaml --ignore-not-found=true
    Print-Success "Cleanup complete"
}

function Show-Menu {
    Print-Header "Module 4 - API Gateway Deployment"
    Write-Host "Select action:`n"
    Write-Host "  1) Deploy gateway"
    Write-Host "  2) Test deployment"
    Write-Host "  3) View logs"
    Write-Host "  4) View metrics"
    Write-Host "  5) Clean up"
    Write-Host "  6) Exit`n"
    $choice = Read-Host "Enter choice [1-6]"

    switch ($choice) {
        "1" { Check-Prerequisites; Deploy-Gateway }
        "2" { Test-Deployment }
        "3" { kubectl logs -l app=api-gateway --tail=50 -f }
        "4" { Print-Info "Port-forwarding... visit http://localhost:8080/metrics"; kubectl port-forward svc/api-gateway-service 8080:80 }
        "5" { Invoke-Cleanup }
        "6" { exit 0 }
        default { Print-Error "Invalid choice"; exit 1 }
    }
}

# Main
$arg = if ($args.Count -gt 0) { $args[0] } else { "" }
switch ($arg) {
    "--deploy" { Check-Prerequisites; Deploy-Gateway }
    "--test"   { Test-Deployment }
    "--clean"  { Invoke-Cleanup }
    ""         { Show-Menu }
    default    { Print-Error "Invalid argument: $arg"; Print-Info "Usage: .\deploy.ps1 [--deploy|--test|--clean]"; exit 1 }
}
