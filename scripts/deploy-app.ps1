param (
    [string]$Namespace = "default",
    [string]$Environment = "staging"
)

# Ensure namespace exists
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -

# Build and load the Docker image into Kind
Write-Host "Building Docker image..." -ForegroundColor Green
docker build -t ghcr.io/karan-wakade/smu:latest .

Write-Host "Loading image into Kind cluster..." -ForegroundColor Green
kind load docker-image ghcr.io/karan-wakade/smu:latest --name smu

# Apply secrets
Write-Host "Applying secrets..." -ForegroundColor Green
./scripts/apply-secrets.ps1 -Namespace $Namespace

# Apply Kubernetes resources
Write-Host "Deploying application resources for environment: $Environment..." -ForegroundColor Green
kubectl apply -k kubernetes/overlays/$Environment -n $Namespace

# Wait for deployment to be ready
$deploymentName = "$Environment-rollout"
Write-Host "Waiting for deployment $deploymentName to be ready..." -ForegroundColor Yellow
kubectl rollout status deployment/$deploymentName -n $Namespace --timeout=120s

# Get service information
$serviceIP = kubectl get service "$deploymentName-service" -n $Namespace -o jsonpath='{.spec.clusterIP}'
$servicePort = kubectl get service "$deploymentName-service" -n $Namespace -o jsonpath='{.spec.ports[0].port}'

Write-Host "Application deployed successfully!" -ForegroundColor Green
# Write-Host "Service available at: http://$serviceIP:$servicePort within the cluster" -ForegroundColor Green
# Write-Host "To access locally, run: kubectl port-forward service/$deploymentName-service $servicePort:$servicePort -n $Namespace" -ForegroundColor Green

# Fix line 34
Write-Host "Service available at: http://${serviceIP}:${servicePort} within the cluster" -ForegroundColor Green

# Fix line 35  
Write-Host "To access locally, run: kubectl port-forward service/$deploymentName-service ${servicePort}:${servicePort} -n $Namespace" -ForegroundColor Green