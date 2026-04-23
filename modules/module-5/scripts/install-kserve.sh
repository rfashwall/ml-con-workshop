#!/bin/bash
set -e

echo "=================================================="
echo "Installing KServe for Model Serving"
echo "=================================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

KSERVE_VERSION="v0.11.0"

echo -e "${YELLOW}Step 1: Installing Istio (required for KServe)...${NC}"

# Install Istio
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.11.0/istio.yaml

# Wait for Istio to be ready
kubectl wait --for=condition=available --timeout=600s deployment/istiod -n istio-system
kubectl wait --for=condition=available --timeout=600s deployment/istio-ingressgateway -n istio-system

echo -e "${GREEN}✓ Istio installed${NC}"
echo ""

echo -e "${YELLOW}Step 2: Installing Knative Serving...${NC}"

# Install Knative Serving
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.11.0/serving-crds.yaml
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.11.0/serving-core.yaml

# Wait for Knative to be ready
kubectl wait --for=condition=available --timeout=600s deployment/webhook -n knative-serving
kubectl wait --for=condition=available --timeout=600s deployment/activator -n knative-serving

echo -e "${GREEN}✓ Knative Serving installed${NC}"
echo ""

echo -e "${YELLOW}Step 3: Installing KServe...${NC}"

# Install cert-manager (required for KServe)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

# Wait for cert-manager
kubectl wait --for=condition=available --timeout=600s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=600s deployment/cert-manager-webhook -n cert-manager

# Install KServe
kubectl apply -f https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve.yaml
kubectl apply -f https://github.com/kserve/kserve/releases/download/${KSERVE_VERSION}/kserve-runtimes.yaml

# gcr.io/kubebuilder/kube-rbac-proxy was removed; patch to the current quay.io mirror
echo -e "${YELLOW}Patching kube-rbac-proxy image (gcr.io retired, redirecting to quay.io)...${NC}"
kubectl set image deployment/kserve-controller-manager -n kserve kube-rbac-proxy=quay.io/brancz/kube-rbac-proxy:v0.13.1

# Wait for KServe
kubectl wait --for=condition=available --timeout=600s deployment/kserve-controller-manager -n kserve

echo -e "${GREEN}✓ KServe installed${NC}"
echo ""

echo -e "${YELLOW}Step 4: Verifying installation...${NC}"
kubectl get pods -n kserve
kubectl get pods -n knative-serving
echo ""

echo -e "${GREEN}=================================================="
echo "KServe Installation Complete!"
echo "==================================================${NC}"
echo ""
echo "You can now deploy InferenceServices with:"
echo "  kubectl apply -f kserve/inference-service.yaml"
echo ""
