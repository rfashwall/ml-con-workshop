# =============================================================================
# Module 7: CI/CD Setup Script
# =============================================================================

$ErrorActionPreference = 'Stop'

Write-Host "======================================" -ForegroundColor Blue
Write-Host "Module 7: Simple CI/CD Setup"          -ForegroundColor Blue
Write-Host "======================================`n" -ForegroundColor Blue

# ==============================================================================
# 1. Check Prerequisites
# ==============================================================================

Write-Host "1. Checking prerequisites..." -ForegroundColor Yellow

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "ERR GitHub CLI (gh) is not installed" -ForegroundColor Red
    Write-Host "    Install from: https://cli.github.com/"
    exit 1
}
Write-Host "OK  GitHub CLI installed" -ForegroundColor Green

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "ERR kubectl is not installed" -ForegroundColor Red
    Write-Host "    Install from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
}
Write-Host "OK  kubectl installed" -ForegroundColor Green

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    Write-Host "ERR kind is not installed" -ForegroundColor Red
    Write-Host "    Install from: https://kind.sigs.k8s.io/docs/user/quick-start/"
    exit 1
}
Write-Host "OK  kind installed" -ForegroundColor Green

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "ERR Docker is not installed" -ForegroundColor Red
    Write-Host "    Install Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
}
Write-Host "OK  Docker installed`n" -ForegroundColor Green

# ==============================================================================
# 2. Check kind Cluster
# ==============================================================================

Write-Host "2. Checking kind cluster..." -ForegroundColor Yellow

$clusters = kind get clusters 2>&1
if ($clusters | Select-String "mlops-workshop") {
    Write-Host "OK  kind cluster 'mlops-workshop' is running" -ForegroundColor Green

    kubectl cluster-info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK  kubectl can connect to cluster`n" -ForegroundColor Green
    } else {
        Write-Host "ERR kubectl cannot connect to cluster" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "WRN kind cluster 'mlops-workshop' not found — creating..." -ForegroundColor Yellow
    kind create cluster --name mlops-workshop
    Write-Host "OK  Cluster created`n" -ForegroundColor Green
}

# ==============================================================================
# 3. Verify Git Repository
# ==============================================================================

Write-Host "3. Checking Git repository..." -ForegroundColor Yellow

git rev-parse --git-dir 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERR Not in a Git repository" -ForegroundColor Red
    Write-Host "    Run: git init && git add . && git commit -m 'Initial commit'"
    exit 1
}
Write-Host "OK  Git repository initialized" -ForegroundColor Green

$remoteUrl = git remote get-url origin 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK  GitHub remote configured: $remoteUrl`n" -ForegroundColor Green
} else {
    Write-Host "WRN No GitHub remote configured" -ForegroundColor Yellow
    Write-Host "    To push code and trigger CI/CD, you need a GitHub repository."
    Write-Host "    Create one and add remote:"
    Write-Host "    gh repo create ml-con-workshop --public --source=. --remote=origin`n" -ForegroundColor Cyan
}

# ==============================================================================
# Summary
# ==============================================================================

Write-Host "======================================" -ForegroundColor Green
Write-Host "OK  Setup Complete!"                   -ForegroundColor Green
Write-Host "======================================`n" -ForegroundColor Green

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Push code to GitHub to trigger the CI/CD workflow:" -ForegroundColor Yellow
Write-Host "   git add ."                                           -ForegroundColor Cyan
Write-Host "   git commit -m 'Add CI/CD workflow'"                 -ForegroundColor Cyan
Write-Host "   git push origin main`n"                             -ForegroundColor Cyan

Write-Host "2. Watch the workflow run:" -ForegroundColor Yellow
Write-Host "   gh run watch"            -ForegroundColor Cyan
Write-Host "   Or visit: https://github.com/<your-username>/<your-repo>/actions`n"

Write-Host "3. After the workflow completes, deploy manually:" -ForegroundColor Yellow
Write-Host "   Follow the deployment instructions in the GitHub Actions summary`n"

Write-Host "4. Test the deployed services:" -ForegroundColor Yellow
Write-Host "   curl http://localhost:30080/health"                                               -ForegroundColor Cyan
Write-Host "   curl -X POST http://localhost:30080/predict -H 'Content-Type: application/json' \`"-ForegroundColor Cyan
Write-Host "        -d '{`"request`": {`"text`": `"This workshop is great!`"}}'`n"              -ForegroundColor Cyan

Write-Host "For more details see: modules/module-7/README.md" -ForegroundColor Yellow
