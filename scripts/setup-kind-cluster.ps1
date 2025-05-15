param (
    [switch]$ForceRecreate = $false,
    [switch]$SkipMonitoring = $false
)

# Check if Kind is installed
if (-not (Get-Command "kind" -ErrorAction SilentlyContinue)) {
    Write-Host "Kind is not installed. Please install it first with: choco install kind" -ForegroundColor Red
    exit 1
}

# Check if Docker is running
try {
    docker version | Out-Null
} catch {
    Write-Host "Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

# Check if cluster already exists
$clusterExists = kind get clusters | Where-Object { $_ -eq "smu" }
if ($clusterExists -and $ForceRecreate) {
    Write-Host "Deleting existing cluster..." -ForegroundColor Yellow
    kind delete cluster --name smu
    $clusterExists = $false
} elseif ($clusterExists) {
    Write-Host "Cluster 'smu' already exists. Use -ForceRecreate to recreate it." -ForegroundColor Yellow
}

# Create cluster if it doesn't exist
if (-not $clusterExists) {
    Write-Host "Creating Kind cluster 'smu'..." -ForegroundColor Green
    kind create cluster --name smu --config kind-config.yaml
    
    # Set current context to the new cluster
    kubectl config use-context kind-smu
    
    # Install ingress-nginx
    Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Green
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    # Wait for ingress to be ready
    Write-Host "Waiting for NGINX Ingress Controller to be ready..." -ForegroundColor Yellow
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
}

# Setup monitoring if not skipped
if (-not $SkipMonitoring) {
    Write-Host "Setting up monitoring with Prometheus and Grafana..." -ForegroundColor Green
    
    # Create monitoring namespace if it doesn't exist
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Prometheus Helm repo if needed
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus stack
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack `
        --namespace monitoring `
        --set grafana.enabled=true `
        --set prometheus.service.type=ClusterIP `
        --set grafana.service.type=ClusterIP
    
    # Wait for Grafana to be ready
Write-Host "Waiting for Grafana to be ready..." -ForegroundColor Yellow
$grafanaReady = $false
$maxAttempts = 12
$attempt = 0

while (-not $grafanaReady -and $attempt -lt $maxAttempts) {
    $attempt++
    Write-Host "Checking Grafana pods (attempt $attempt/$maxAttempts)..." -ForegroundColor Yellow
    
    $pods = kubectl get pods -n monitoring -l "app.kubernetes.io/name=grafana" -o jsonpath="{.items[*].status.phase}"
    if ($pods -eq "Running") {
        $grafanaReady = $true
        Write-Host "Grafana pod is running!" -ForegroundColor Green
    } else {
        Write-Host "Grafana pod not ready yet, waiting 10 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
}

# Get Grafana admin password with error handling
$adminPassword = "admin"  # Default fallback
try {
    Write-Host "Attempting to retrieve Grafana admin password..." -ForegroundColor Yellow
    
    # Wait a bit for the secret to be available
    Start-Sleep -Seconds 5
    
    $encodedPassword = kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" 2>$null
    
    if ($encodedPassword) {
        $adminPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPassword))
        Write-Host "Successfully retrieved Grafana password." -ForegroundColor Green
    } else {
        Write-Host "Couldn't retrieve Grafana password. Using default 'admin'." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Error retrieving Grafana password: $_" -ForegroundColor Yellow
    Write-Host "Using default password 'admin' instead." -ForegroundColor Yellow
}

Write-Host "Grafana is available at: http://localhost:3000" -ForegroundColor Green
Write-Host "Username: admin" -ForegroundColor Green
Write-Host "Password: $adminPassword" -ForegroundColor Green
}

# Display success message
Write-Host "Kind cluster 'smu' is ready for use!" -ForegroundColor Green
Write-Host "Current context: $(kubectl config current-context)" -ForegroundColor Green
Write-Host "To run the full application stack, use: ./scripts/deploy-app.ps1" -ForegroundColor Green