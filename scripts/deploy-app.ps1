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

# Try a few times in case it times out
$maxAttempts = 3
$success = $false

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        Write-Host "Attempt $attempt of $maxAttempts..." -ForegroundColor Yellow
        kubectl rollout status deployment/$deploymentName -n $Namespace --timeout=60s
        $success = $true
        break
    } catch {
        Write-Host "Deployment status check timed out, checking deployment status..." -ForegroundColor Yellow
        kubectl get deployment $deploymentName -n $Namespace
    }
}

# Get service information
$serviceIP = kubectl get service "$deploymentName-service" -n $Namespace -o jsonpath='{.spec.clusterIP}'
$servicePort = kubectl get service "$deploymentName-service" -n $Namespace -o jsonpath='{.spec.ports[0].port}'

Write-Host "Application deployed successfully!" -ForegroundColor Green
Write-Host "Service available at: http://$serviceIP:$servicePort within the cluster" -ForegroundColor Green
Write-Host "To access locally, run: ./scripts/port-forward.ps1 -Environment $Environment -LocalPort 8080" -ForegroundColor Green
