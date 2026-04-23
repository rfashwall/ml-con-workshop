#!/bin/bash

# =============================================================================
# Module 4 - Build Script for API Gateway
# =============================================================================
#
# This script builds the Go API Gateway and creates a Docker image.
# Supports local development and production builds.
#
# Usage:
#   ./build.sh                 # Interactive mode
#   ./build.sh --local         # Build for local testing
#   ./build.sh --docker        # Build Docker image
#   ./build.sh --kind          # Build and load into kind
#   ./build.sh --all           # Build everything
#

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
IMAGE_NAME="api-gateway"
IMAGE_TAG="v1"
FULL_IMAGE="$IMAGE_NAME:$IMAGE_TAG"
CLUSTER_NAME="mlops-workshop"

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

    # Check Go
    if ! command -v go &> /dev/null; then
        print_error "Go not found. Please install Go 1.21 or later."
        exit 1
    fi
    GO_VERSION=$(go version | awk '{print $3}')
    print_success "Go found: $GO_VERSION"

    # Check Docker (if building image)
    if [[ "$1" == "docker" ]] || [[ "$1" == "kind" ]] || [[ "$1" == "all" ]]; then
        if ! command -v docker &> /dev/null; then
            print_error "Docker not found. Please install Docker."
            exit 1
        fi
        print_success "Docker found"

        if ! docker info &> /dev/null; then
            print_error "Docker daemon not running. Please start Docker."
            exit 1
        fi
        print_success "Docker daemon running"
    fi

    # Check kind (if loading into kind)
    if [[ "$1" == "kind" ]] || [[ "$1" == "all" ]]; then
        if ! command -v kind &> /dev/null; then
            print_error "kind not found. Please install kind."
            exit 1
        fi
        print_success "kind found"

        if ! kind get clusters | grep -q "$CLUSTER_NAME"; then
            print_error "kind cluster '$CLUSTER_NAME' not found."
            print_info "Create it with: kind create cluster --name $CLUSTER_NAME"
            exit 1
        fi
        print_success "kind cluster '$CLUSTER_NAME' found"
    fi
}

# Download Go dependencies
download_deps() {
    print_header "Downloading Go Dependencies"

    if [[ ! -f "go.mod" ]]; then
        print_error "go.mod not found. Are you in the module-4 directory?"
        exit 1
    fi

    print_info "Running go mod download..."
    if go mod download; then
        print_success "Dependencies downloaded"
    else
        print_error "Failed to download dependencies"
        exit 1
    fi

    # Verify dependencies
    print_info "Verifying dependencies..."
    if go mod verify; then
        print_success "Dependencies verified"
    else
        print_warning "Dependency verification failed (may be OK)"
    fi
}

# Build local binary (for testing)
build_local() {
    print_header "Building Local Binary"

    print_info "Building gateway binary..."
    if go build -o gateway starter/gateway.go; then
        print_success "Binary built: ./gateway"

        # Show binary info
        if command -v file &> /dev/null; then
            file ./gateway
        fi

        BINARY_SIZE=$(du -h ./gateway | cut -f1)
        print_info "Binary size: $BINARY_SIZE"

        print_info ""
        print_info "Run locally with:"
        print_info "  export BACKEND_URL=http://localhost:3000"
        print_info "  export LOG_LEVEL=debug"
        print_info "  ./gateway"
    else
        print_error "Build failed"
        exit 1
    fi
}

# Build Docker image
build_docker() {
    print_header "Building Docker Image"

    print_info "Building $FULL_IMAGE..."
    print_info "This may take a few minutes on first build..."

    # Build with timing
    START_TIME=$(date +%s)

    if docker build -t $FULL_IMAGE .; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))

        print_success "Docker image built in ${DURATION}s"

        # Show image info
        print_header "Image Information"
        docker images | grep -E "REPOSITORY|$IMAGE_NAME"

        IMAGE_SIZE=$(docker images $FULL_IMAGE --format "{{.Size}}")
        print_info "Image size: $IMAGE_SIZE"

        print_info ""
        print_info "Run container with:"
        print_info "  docker run -p 8080:8080 \\"
        print_info "    -e BACKEND_URL=http://host.docker.internal:3000 \\"
        print_info "    -e LOG_LEVEL=debug \\"
        print_info "    $FULL_IMAGE"
    else
        print_error "Docker build failed"
        exit 1
    fi
}

# Load image into kind
load_kind() {
    print_header "Loading Image into kind Cluster"

    # Check if image exists
    if ! docker images | grep -q "$IMAGE_NAME.*$IMAGE_TAG"; then
        print_error "Docker image '$FULL_IMAGE' not found"
        print_info "Build it first with: ./build.sh --docker"
        exit 1
    fi

    print_info "Loading $FULL_IMAGE into kind cluster '$CLUSTER_NAME'..."
    if kind load docker-image $FULL_IMAGE --name $CLUSTER_NAME; then
        print_success "Image loaded into kind"

        # Verify
        print_info "Verifying image in kind..."
        if docker exec ${CLUSTER_NAME}-control-plane crictl images | grep -q "$IMAGE_NAME"; then
            print_success "Image verified in kind"
        else
            print_warning "Could not verify (but load succeeded)"
        fi
    else
        print_error "Failed to load image into kind"
        exit 1
    fi
}

# Test build (compile only, no binary output)
test_build() {
    print_header "Testing Build"

    print_info "Running go build -o /dev/null..."
    if go build -o /dev/null starter/gateway.go; then
        print_success "Build test passed"
    else
        print_error "Build test failed"
        exit 1
    fi
}

# Run tests
run_tests() {
    print_header "Running Tests"

    print_info "Looking for test files..."
    if ls *_test.go &> /dev/null; then
        print_info "Running go test..."
        if go test -v ./...; then
            print_success "Tests passed"
        else
            print_error "Tests failed"
            exit 1
        fi
    else
        print_warning "No test files found"
        print_info "You should add tests! Example: gateway_test.go"
    fi
}

# Interactive menu
show_menu() {
    print_header "Module 4 - API Gateway Builder"

    echo "Select build option:"
    echo ""
    echo "  1) Download dependencies only"
    echo "  2) Build local binary (for testing)"
    echo "  3) Build Docker image"
    echo "  4) Load Docker image into kind"
    echo "  5) Build everything (binary + Docker + kind)"
    echo "  6) Test build (no output)"
    echo "  7) Run tests"
    echo "  8) Exit"
    echo ""
    read -p "Enter choice [1-8]: " choice

    case $choice in
        1)
            check_prerequisites "local"
            download_deps
            ;;
        2)
            check_prerequisites "local"
            download_deps
            build_local
            ;;
        3)
            check_prerequisites "docker"
            build_docker
            ;;
        4)
            check_prerequisites "kind"
            load_kind
            ;;
        5)
            check_prerequisites "all"
            download_deps
            build_local
            build_docker
            load_kind
            print_success ""
            print_success "All builds complete!"
            print_info "Next: Deploy with kubectl apply -f deployment.yaml"
            ;;
        6)
            check_prerequisites "local"
            test_build
            ;;
        7)
            check_prerequisites "local"
            download_deps
            run_tests
            ;;
        8)
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
        show_menu
    else
        # Command-line mode
        case "$1" in
            --local)
                check_prerequisites "local"
                download_deps
                build_local
                ;;
            --docker)
                check_prerequisites "docker"
                build_docker
                ;;
            --kind)
                check_prerequisites "kind"
                load_kind
                ;;
            --all)
                check_prerequisites "all"
                download_deps
                build_local
                build_docker
                load_kind
                print_success ""
                print_success "All builds complete!"
                ;;
            --test)
                check_prerequisites "local"
                test_build
                ;;
            --deps)
                check_prerequisites "local"
                download_deps
                ;;
            *)
                print_error "Invalid argument: $1"
                print_info "Usage: $0 [--local|--docker|--kind|--all|--test|--deps]"
                exit 1
                ;;
        esac
    fi
}

# Run main
main "$@"
