# Multi-Stage Docker Build for Go API Gateway
# ============================================
#
# This Dockerfile demonstrates Go best practices:
# - Multi-stage build (smaller final image)
# - Separate build and runtime stages
# - Non-root user (security)
# - Minimal base image (distroless)
#
# Final image size: ~25MB (vs ~800MB with full Go image!)

# =============================================================================
# STAGE 1: BUILD
# =============================================================================
# Use official Golang image as build environment
# This image has all build tools but is large (~800MB)
FROM golang:1.21-alpine AS builder

# Install build dependencies
# - git: for fetching Go modules from git repositories
# - ca-certificates: for HTTPS requests during build
RUN apk add --no-cache git ca-certificates

# Set working directory
WORKDIR /build

# Copy go.mod and go.sum first (layer caching optimization)
# If these files don't change, Docker reuses the cached layer
# This makes rebuilds faster when only code changes
COPY go.mod go.sum ./

# Download dependencies
# This layer is cached unless go.mod/go.sum changes
RUN go mod download

# Copy source code — students' completed gateway lives in starter/
COPY starter/gateway.go ./gateway.go

# Build the binary
# Flags explained:
#   -o gateway          - Output filename
#   -ldflags="-w -s"    - Strip debug info (smaller binary)
#   -trimpath           - Remove file system paths (security)
#   CGO_ENABLED=0       - Static binary (no C dependencies)
#   GOOS=linux          - Target OS
#   GOARCH=amd64        - Target architecture
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -trimpath \
    -o gateway \
    gateway.go

# =============================================================================
# STAGE 2: RUNTIME
# =============================================================================
# Use minimal base image
# gcr.io/distroless/static-debian11 contains:
# - Only essential runtime files
# - CA certificates (for HTTPS)
# - No shell, no package manager (more secure)
# - Size: ~2MB
FROM gcr.io/distroless/static-debian11

# Add labels for metadata
LABEL maintainer="mlops-workshop" \
      description="API Gateway for Sentiment Analysis Service" \
      version="2.0.0"

# Copy CA certificates from builder (for HTTPS requests to backend)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the binary from builder stage
COPY --from=builder /build/gateway /gateway

# Use non-root user (security best practice)
# distroless images provide nonroot user (UID 65532)
USER nonroot:nonroot

# Expose port
# This is documentation only - doesn't actually publish the port
EXPOSE 8080

# Health check (optional but recommended)
# Docker/Kubernetes can use this to check container health
# Note: distroless doesn't have curl/wget, so we rely on K8s health probes
# HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
#   CMD ["/gateway", "healthcheck"]

# Run the binary
# distroless images use ENTRYPOINT instead of CMD
ENTRYPOINT ["/gateway"]

# =============================================================================
# BUILD COMMANDS
# =============================================================================
#
# Build the image:
#   docker build -t api-gateway:v1 .
#
# Build with build arguments (for versioning):
#   docker build \
#     --build-arg VERSION=2.0.0 \
#     --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
#     -t api-gateway:v1 .
#
# Run locally:
#   docker run -p 8080:8080 \
#     -e BACKEND_URL=http://host.docker.internal:3000 \
#     -e LOG_LEVEL=debug \
#     api-gateway:v1
#
# Run with Docker Compose (alongside ML service):
#   See docker-compose.yml
#
# Multi-platform build (for M1 Mac → Linux deployment):
#   docker buildx build \
#     --platform linux/amd64,linux/arm64 \
#     -t api-gateway:v1 \
#     --load .
#
# =============================================================================
# WHY MULTI-STAGE BUILDS?
# =============================================================================
#
# Single-stage build (traditional):
# ┌─────────────────────────────────┐
# │ golang:1.21 (~800MB)           │
# │ ├─ Go compiler                  │
# │ ├─ Build tools                  │
# │ ├─ Source code                  │
# │ └─ Binary (15MB)                │
# └─────────────────────────────────┘
# Final image: 800MB ❌
#
# Multi-stage build (modern):
# ┌─────────────────────────────────┐
# │ STAGE 1: Builder               │
# │ golang:1.21 (~800MB)           │
# │ ├─ Go compiler                  │
# │ ├─ Build tools                  │
# │ ├─ Source code                  │
# │ └─ Binary (15MB) ──┐           │
# └────────────────────│────────────┘
#                      │
#                      ↓ Copy only binary
# ┌────────────────────────────────┐
# │ STAGE 2: Runtime               │
# │ distroless (~2MB)              │
# │ └─ Binary (15MB)               │
# └────────────────────────────────┘
# Final image: 17MB ✅
#
# Benefits:
# ✅ 98% smaller image (800MB → 17MB)
# ✅ Faster deployments (less data to transfer)
# ✅ Smaller attack surface (no build tools in production)
# ✅ Faster container startup
# ✅ Lower storage costs
#
# =============================================================================
# SECURITY FEATURES
# =============================================================================
#
# 1. Distroless base image
#    - No shell (can't exec into container)
#    - No package manager (can't install malware)
#    - Minimal attack surface
#
# 2. Non-root user
#    - Runs as UID 65532 (nonroot)
#    - Can't modify system files
#    - Limited privileges
#
# 3. Static binary
#    - No dynamic libraries
#    - No dependency vulnerabilities
#    - Works on any Linux distro
#
# 4. Stripped binary
#    - Debug symbols removed (-ldflags="-w -s")
#    - Harder to reverse engineer
#    - Smaller binary size
#
# 5. No file system paths
#    - -trimpath flag removes build paths
#    - Prevents information leakage
#
# =============================================================================
# COMPARISON WITH PYTHON ML SERVICE
# =============================================================================
#
# Python (BentoML) Container:
# ├─ Base: python:3.11 (~900MB)
# ├─ Dependencies: transformers, torch (~2GB)
# ├─ Model files: ~250MB
# └─ Total: ~3.2GB
#
# Go Gateway Container:
# ├─ Base: distroless (~2MB)
# ├─ Binary: ~15MB
# └─ Total: ~17MB
#
# Ratio: Go is 188x smaller! 🚀
#
# Why?
# - Go compiles to native code (no runtime needed)
# - Python needs interpreter + libraries
# - ML models are large (unavoidable)
#
# This is why polyglot architecture makes sense:
# - Lightweight Go for routing/gateway (fast, small)
# - Python for ML (ecosystem, libraries)
#
# =============================================================================
