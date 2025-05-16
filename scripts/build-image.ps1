# Exit on error
$ErrorActionPreference = "Stop"

# Point Docker client to Minikube's Docker daemon
Write-Host "Pointing Docker client to Minikube's Docker daemon..."
& minikube docker-env | Invoke-Expression

# Build the image
Write-Host "Building Docker image..."
docker build -t ghcr.io/karan-wakade/smu:latest .

# No need to "docker push" for local development
# The image is already available to Minikube
Write-Host "Docker image built and available to Minikube."