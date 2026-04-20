#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Installing KServe for Model Serving" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$KSERVE_VERSION = "v0.11.0"

Write-Host "Step 1: Installing Istio (required for KServe)..." -ForegroundColor Yellow

kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.11.0/istio.yaml

kubectl wait --for=condition=available --timeout=600s deployment/istiod -n istio-system
kubectl wait --for=condition=available --timeout=600s deployment/istio-ingressgateway -n istio-system

Write-Host "[OK] Istio installed" -ForegroundColor Green
Write-Host ""

Write-Host "Step 2: Installing Knative Serving..." -ForegroundColor Yellow

kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.11.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.11.0/serving-core.yaml

kubectl wait --for=condition=available --timeout=600s deployment/webhook -n knative-serving
kubectl wait --for=condition=available --timeout=600s deployment/activator -n knative-serving

Write-Host "[OK] Knative Serving installed" -ForegroundColor Green
Write-Host ""

Write-Host "Step 3: Installing KServe..." -ForegroundColor Yellow

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

kubectl wait --for=condition=available --timeout=600s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=600s deployment/cert-manager-webhook -n cert-manager

kubectl apply -f "https://github.com/kserve/kserve/releases/download/$KSERVE_VERSION/kserve.yaml"
kubectl apply -f "https://github.com/kserve/kserve/releases/download/$KSERVE_VERSION/kserve-runtimes.yaml"

# gcr.io/kubebuilder/kube-rbac-proxy was removed; patch to the current quay.io mirror
Write-Host "Patching kube-rbac-proxy image (gcr.io retired, redirecting to quay.io)..." -ForegroundColor Yellow
kubectl set image deployment/kserve-controller-manager -n kserve kube-rbac-proxy=quay.io/brancz/kube-rbac-proxy:v0.13.1

kubectl wait --for=condition=available --timeout=600s deployment/kserve-controller-manager -n kserve

Write-Host "[OK] KServe installed" -ForegroundColor Green
Write-Host ""

Write-Host "Step 4: Verifying installation..." -ForegroundColor Yellow
kubectl get pods -n kserve
kubectl get pods -n knative-serving
Write-Host ""

Write-Host "==================================================" -ForegroundColor Green
Write-Host "KServe Installation Complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green
Write-Host ""
Write-Host "You can now deploy InferenceServices with:"
Write-Host "  kubectl apply -f kserve/inference-service.yaml"
Write-Host ""
