#!/bin/bash
# =============================================================================
# Anonymous India - EC2 Deployment Script
# Pulls and deploys Docker image on Ubuntu EC2
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/.env"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Installing..."
        install_docker
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose plugin not found. Installing..."
        install_docker_compose
    fi
    
    log_success "Prerequisites check passed"
}

# Install Docker on Ubuntu
install_docker() {
    log_info "Installing Docker..."
    
    # Remove old versions
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install dependencies
    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group
    usermod -aG docker $USER || true
    
    log_success "Docker installed successfully"
}

# Install Docker Compose
install_docker_compose() {
    log_info "Installing Docker Compose..."
    
    # It's already installed with docker-ce package in modern versions
    # This is just a fallback
    apt-get update
    apt-get install -y docker-compose-plugin
    
    log_success "Docker Compose installed"
}

# Login to registry (ECR, Docker Hub, etc.)
login_registry() {
    if [[ -n "${REGISTRY:-}" ]]; then
        log_info "Logging into registry: $REGISTRY"
        
        # Check if it's AWS ECR
        if [[ "$REGISTRY" == *"amazonaws.com"* ]]; then
            # Install AWS CLI if needed
            if ! command -v aws &> /dev/null; then
                log_info "Installing AWS CLI..."
                apt-get update && apt-get install -y unzip
                curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                unzip awscliv2.zip
                ./aws/install
                rm -rf aws awscliv2.zip
            fi
            
            # Login to ECR
            aws ecr get-login-password --region ${AWS_REGION:-ap-south-1} | \
                docker login --username AWS --password-stdin "$REGISTRY"
        fi
        
        log_success "Registry login successful"
    fi
}

# Pull latest image
pull_image() {
    log_info "Pulling latest image..."
    
    local image="${REGISTRY:-}${IMAGE_NAME:-anonymous-backend}:${TAG:-latest}"
    
    docker pull "$image"
    
    log_success "Image pulled: $image"
}

# Deploy the application
deploy() {
    log_info "Deploying application..."
    
    cd "$PROJECT_DIR"
    
    # Check if .env exists
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at $ENV_FILE"
        log_info "Please create .env file from .env.example"
        exit 1
    fi
    
    # Stop existing containers
    log_info "Stopping existing containers..."
    docker compose -f docker-compose.prod.yml down || true
    
    # Remove old images to save space
    log_info "Cleaning up old images..."
    docker image prune -af --filter "until=168h" || true
    
    # Start new containers
    log_info "Starting new containers..."
    docker compose -f docker-compose.prod.yml up -d
    
    # Wait for health check
    log_info "Waiting for health check..."
    sleep 10
    
    # Check if API is healthy
    if curl -fs http://localhost:3001/api/health &> /dev/null; then
        log_success "Deployment successful! API is healthy."
    else
        log_warn "API health check failed. Checking logs..."
        docker compose -f docker-compose.prod.yml logs api --tail 50
        exit 1
    fi
}

# Show status
show_status() {
    log_info "Container Status:"
    docker compose -f docker-compose.prod.yml ps
    
    echo
    log_info "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

# Backup database
backup_db() {
    log_info "Creating database backup..."
    
    local backup_dir="${PROJECT_DIR}/backups"
    mkdir -p "$backup_dir"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/backup_${timestamp}.sql"
    
    # Load environment variables
    source "$ENV_FILE"
    
    # Create backup
    docker exec anonymous-postgres pg_dump \
        -U "${DB_USER:-anonymous}" \
        -d "${DB_NAME:-anonymous_india}" \
        > "$backup_file"
    
    # Compress
    gzip "$backup_file"
    
    log_success "Backup created: ${backup_file}.gz"
    
    # Keep only last 7 backups
    find "$backup_dir" -name "backup_*.sql.gz" -type f -mtime +7 -delete
}

# Rollback to previous version
rollback() {
    log_warn "Rolling back to previous version..."
    
    # TODO: Implement rollback logic based on your tagging strategy
    log_error "Rollback not implemented yet. Please specify a previous tag."
    exit 1
}

# Show logs
show_logs() {
    local service="${1:-api}"
    docker compose -f docker-compose.prod.yml logs -f "$service"
}

# Display usage
show_usage() {
    cat << EOF
Anonymous India - EC2 Deployment Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    deploy          Full deployment (pull image, stop, start)
    pull            Pull latest image only
    start           Start containers
    stop            Stop containers
    restart         Restart containers
    status          Show container status
    logs [service]  Show logs (default: api)
    backup          Create database backup
    update          Update deployment scripts
    setup           Install Docker and prerequisites

Options:
    -e, --env FILE    Use specific env file (default: .env)
    -t, --tag TAG     Use specific image tag
    -h, --help        Show this help

Examples:
    # Full deployment
    $0 deploy

    # Deploy specific version
    $0 deploy --tag v1.2.3

    # View logs
    $0 logs api

    # Create backup
    $0 backup

Environment Variables:
    REGISTRY        Docker registry URL
    IMAGE_NAME      Image name (default: anonymous-backend)
    TAG             Image tag (default: latest)
    AWS_REGION      AWS region for ECR (default: ap-south-1)

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--env)
                ENV_FILE="$2"
                shift 2
                ;;
            -t|--tag)
                export TAG="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            deploy|pull|start|stop|restart|status|logs|backup|update|setup)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    COMMAND="${1:-deploy}"
    
    parse_args "$@"
    
    case "$COMMAND" in
        setup)
            check_prerequisites
            ;;
        deploy)
            check_prerequisites
            login_registry
            pull_image
            backup_db
            deploy
            show_status
            ;;
        pull)
            login_registry
            pull_image
            ;;
        start)
            cd "$PROJECT_DIR"
            docker compose -f docker-compose.prod.yml up -d
            ;;
        stop)
            cd "$PROJECT_DIR"
            docker compose -f docker-compose.prod.yml down
            ;;
        restart)
            cd "$PROJECT_DIR"
            docker compose -f docker-compose.prod.yml restart
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-api}"
            ;;
        backup)
            backup_db
            ;;
        update)
            log_info "Updating deployment scripts..."
            git pull
            log_success "Scripts updated"
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
