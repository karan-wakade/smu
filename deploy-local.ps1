# Login to GitHub Container Registry
Write-Host "Logging in to GitHub Container Registry..."
$env:GHCR_PAT | docker login ghcr.io -u karan-wakade --password-stdin

# Apply Kubernetes configurations
Write-Host "Applying Kubernetes configurations..."
kubectl apply -f .\k8s\base\namespace.yaml
kubectl apply -f .\k8s\monitoring\
kubectl apply -f .\k8s\

# Set up auto-tuning
Write-Host "Setting up auto-tuning..."
kubectl apply -f .\k8s\auto-tuning\

# Wait for deployments to be ready
Write-Host "Waiting for deployments to be ready..."
kubectl rollout status deployment/smu-frontend -n smu-system
kubectl rollout status deployment/smu-backend -n smu-system

Write-Host "Application deployed successfully!" -ForegroundColor Green