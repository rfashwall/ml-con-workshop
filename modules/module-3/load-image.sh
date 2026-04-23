#!/bin/bash

# =============================================================================
# Module 3 - Docker Image Loader for kind
# =============================================================================
#
# This script helps you build and load the Docker image into kind cluster
# Handles the complete workflow from Module 2 to Module 3
#
# Usage:
#   ./load-image.sh           # Interactive mode
#   ./load-image.sh --build   # Build and load
#   ./load-image.sh --load    # Load only (if already built)
#
# Prerequisites:
#   - kind cluster running
#   - BentoML installed (for building)
#   - Docker running
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="sentiment-api"
IMAGE_TAG="v1"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
CLUSTER_NAME="mlops-workshop"
MODULE2_PATH="../module-2"

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first."
        exit 1
    fi
    print_success "Docker found"

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    print_success "Docker daemon running"

    # Check kind
    if ! command -v kind &> /dev/null; then
        print_error "kind not found. Please install kind first."
        exit 1
    fi
    print_success "kind found"

    # Check if kind cluster exists
    if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
        print_error "kind cluster '$CLUSTER_NAME' not found."
        print_info "Create it with: kind create cluster --name $CLUSTER_NAME"
        exit 1
    fi
    print_success "kind cluster '$CLUSTER_NAME' found"

    # Check BentoML (for building)
    if [[ "$1" == "build" ]]; then
        if ! command -v bentoml &> /dev/null; then
            print_error "BentoML not found. Install it to build the image."
            print_info "Install with: pip install bentoml"
            exit 1
        fi
        print_success "BentoML found"
    fi
}

# Check if image exists locally
check_image_exists() {
    if docker images | grep -q "$IMAGE_NAME.*$IMAGE_TAG"; then
        return 0
    else
        return 1
    fi
}

# Check if image is loaded in kind
check_image_in_kind() {
    if docker exec ${CLUSTER_NAME}-control-plane crictl images | grep -q "$IMAGE_NAME"; then
        return 0
    else
        return 1
    fi
}

# Build Docker image using BentoML
build_image() {
    print_header "Building Docker Image"

    # Check if Module 2 directory exists
    if [[ ! -d "$MODULE2_PATH" ]]; then
        print_error "Module 2 directory not found: $MODULE2_PATH"
        print_info "Make sure you're running this script from modules/module-3/"
        exit 1
    fi

    # Check if we have a saved model
    print_info "Checking for saved BentoML models..."
    cd "$MODULE2_PATH"

    if ! bentoml models list 2>/dev/null | grep -q "sentiment"; then
        print_warning "No sentiment model found in BentoML store"
        print_info "Need to save a model first."
        print_info ""
        print_info "Options:"
        print_info "  1. Run one of the service files to save a model:"
        print_info "     python step1_basic_service.py"
        print_info ""
        print_info "  2. Or train a model from Module 1:"
        print_info "     cd ../module-1"
        print_info "     python train.py"
        print_info ""
        exit 1
    fi

    print_success "BentoML model found"

    # Check if we have a built Bento
    print_info "Checking for built Bentos..."
    if ! bentoml list 2>/dev/null | grep -q "sentiment_service"; then
        print_warning "No sentiment_service Bento found"
        print_info "Building Bento first..."

        # Check if bentofile.yaml exists
        if [[ ! -f "bentofile.yaml" ]]; then
            print_error "bentofile.yaml not found in $MODULE2_PATH"
            exit 1
        fi

        # Build Bento
        if bentoml build; then
            print_success "Bento built successfully"
        else
            print_error "Failed to build Bento"
            exit 1
        fi
    else
        print_success "Bento found"
    fi

    # Get latest Bento tag
    local bento_tag=$(bentoml list sentiment_service -o json | jq -r '.[0].tag' 2>/dev/null || echo "latest")
    print_info "Using Bento: sentiment_service:$bento_tag"

    # Containerize
    print_info "Containerizing Bento..."
    print_info "This may take a few minutes..."
    print_info ""

    if bentoml containerize sentiment_service:$bento_tag -t $FULL_IMAGE; then
        print_success "Docker image built: $FULL_IMAGE"
    else
        print_error "Failed to build Docker image"
        exit 1
    fi

    # Return to module-3
    cd - > /dev/null

    # Show image details
    print_header "Image Details"
    docker images | grep -E "REPOSITORY|$IMAGE_NAME"
}

# Load image into kind cluster
load_image() {
    print_header "Loading Image into kind Cluster"

    # Check if image exists locally
    if ! check_image_exists; then
        print_error "Docker image '$FULL_IMAGE' not found locally"
        print_info "Build it first with: ./load-image.sh --build"
        exit 1
    fi

    print_info "Loading $FULL_IMAGE into kind cluster '$CLUSTER_NAME'..."
    print_info "This may take a minute..."

    if kind load docker-image $FULL_IMAGE --name $CLUSTER_NAME; then
        print_success "Image loaded successfully"
    else
        print_error "Failed to load image into kind"
        exit 1
    fi

    # Verify
    print_info "Verifying image in kind cluster..."
    if check_image_in_kind; then
        print_success "Image verified in kind cluster"

        print_header "Image Information in kind"
        docker exec ${CLUSTER_NAME}-control-plane crictl images | grep -E "IMAGE|$IMAGE_NAME"
    else
        print_warning "Could not verify image in kind (but load command succeeded)"
    fi
}

# Interactive menu
show_menu() {
    print_header "Module 3 - Docker Image Loader"

    echo "Current status:"
    echo ""

    # Check local image
    if check_image_exists; then
        echo -e "  ${GREEN}✅ Docker image exists locally${NC}"
        docker images | grep "$IMAGE_NAME.*$IMAGE_TAG"
    else
        echo -e "  ${RED}❌ Docker image not found locally${NC}"
    fi
    echo ""

    # Check image in kind
    if check_image_in_kind; then
        echo -e "  ${GREEN}✅ Image loaded in kind cluster${NC}"
    else
        echo -e "  ${RED}❌ Image not loaded in kind cluster${NC}"
    fi
    echo ""

    echo "What would you like to do?"
    echo ""
    echo "  1) Build Docker image (using BentoML)"
    echo "  2) Load image into kind cluster"
    echo "  3) Build AND load (complete workflow)"
    echo "  4) Check status only"
    echo "  5) Exit"
    echo ""
    read -p "Enter choice [1-5]: " choice

    case $choice in
        1)
            check_prerequisites "build"
            build_image
            print_info ""
            print_info "Next step: Load the image with option 2 or run ./load-image.sh --load"
            ;;
        2)
            check_prerequisites "load"
            load_image
            print_info ""
            print_info "Next step: Deploy to Kubernetes with ./deploy.sh"
            ;;
        3)
            check_prerequisites "build"
            build_image
            load_image
            print_success ""
            print_success "Complete! Image built and loaded."
            print_info "Next step: Deploy to Kubernetes with ./deploy.sh"
            ;;
        4)
            print_info "Status check complete"
            ;;
        5)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Main script
main() {
    if [[ $# -eq 0 ]]; then
        # Interactive mode
        check_prerequisites "build"
        show_menu
    else
        # Command-line mode
        case "$1" in
            --build)
                check_prerequisites "build"
                build_image
                print_info ""
                print_info "Image built but not loaded into kind yet."
                print_info "Run: ./load-image.sh --load"
                ;;
            --load)
                check_prerequisites "load"
                load_image
                ;;
            --all)
                check_prerequisites "build"
                build_image
                load_image
                print_success ""
                print_success "Complete! Image built and loaded."
                print_info "Next: ./deploy.sh"
                ;;
            *)
                print_error "Invalid argument: $1"
                print_info "Usage: $0 [--build|--load|--all]"
                exit 1
                ;;
        esac
    fi
}

# Run main function
main "$@"
