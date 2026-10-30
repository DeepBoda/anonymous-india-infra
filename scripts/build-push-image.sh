#!/bin/bash
# =============================================================================
# Anonymous India - Quick Docker Build & Push for EC2
# Builds AMD64 only (fastest for EC2 deployment)
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

# Config
IMAGE_NAME="${IMAGE_NAME:-deepboda/anonymous-backend}"
TAG="${TAG:-latest}"
START_TIME=$(date +%s)

# Helpers
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
success() { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $1"; }

elapsed() {
    local duration=$(($(date +%s) - START_TIME))
    printf "%02d:%02d" $((duration/60)) $((duration%60))
}

# Build and push for AMD64 (EC2)
build_amd64() {
    log "Building ${BOLD}${IMAGE_NAME}:${TAG}${NC} for EC2 (AMD64)..."
    echo
    
    # Use Docker buildx with platform flag
    docker buildx build \
        --platform linux/amd64 \
        --tag "${IMAGE_NAME}:${TAG}" \
        --tag "${IMAGE_NAME}:latest" \
        --push \
        --file Dockerfile \
        .
    
    success "Build & push completed"
}

# Verify manifest
verify() {
    log "Verifying image..."
    docker manifest inspect "${IMAGE_NAME}:${TAG}" 2>/dev/null | \
        grep -o '"architecture": "[^"]*"' | \
        sed 's/"architecture": /  🖥  /' | \
        sed 's/"//g' || \
        warn "Could not verify manifest"
}

# Main
main() {
    echo -e "${BOLD}"
    echo "╔═══════════════════════════════════════════════╗"
    echo "║  Anonymous India - Docker Build for EC2       ║"
    echo "║  Target: AMD64 (Ubuntu EC2)                   ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    cd "$(dirname "$0")/.."
    
    # Ensure buildx is using default builder
    docker buildx use default 2>/dev/null || true
    
    # Build and push
    build_amd64
    verify
    
    echo
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    success "Ready for EC2 deployment!"
    echo -e "  ⏱  Time: ${GREEN}$(elapsed)${NC}"
    echo -e "  📦 Image: ${YELLOW}${IMAGE_NAME}:${TAG}${NC}"
    echo -e "  🖥  Platform: ${YELLOW}linux/amd64${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "On your EC2 server, run:"
    echo -e "  ${BLUE}./scripts/deploy-docker.sh${NC}"
    echo
}

main "$@"
