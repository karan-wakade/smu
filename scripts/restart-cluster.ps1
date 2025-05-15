param (
    [switch]$ForceRecreate = $false
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

# Check if cluster exists
$clusterExists = kind get clusters | Where-Object { $_ -eq "smu" }
if ($clusterExists -and $ForceRecreate) {
    Write-Host "Deleting existing cluster..." -ForegroundColor Yellow
    kind delete cluster --name smu
    kind create cluster --name smu --config kind-config.yaml
    
    # Set current context to the new cluster
    kubectl config use-context kind-smu
    
    # Install ingress-nginx
    Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Green
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    Write-Host "Cluster has been recreated. Please run scripts/deploy-app.ps1 to redeploy your application." -ForegroundColor Green
} elseif ($clusterExists) {
    Write-Host "Restarting Docker container for Kind cluster..." -ForegroundColor Yellow
    docker restart kind-control-plane kind-worker
    
    # Wait for cluster to be ready
    Write-Host "Waiting for cluster to be ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Set current context
    kubectl config use-context kind-smu
    
    # Wait for node to be ready
    $ready = $false
    $attempts = 0
    $maxAttempts = 12
    
    while (-not $ready -and $attempts -lt $maxAttempts) {
        $attempts++
        $nodeStatus = kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
        
        if ($nodeStatus -eq "True") {
            $ready = $true
        } else {
            Write-Host "Waiting for nodes to be ready (attempt $attempts/$maxAttempts)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }
    
    if ($ready) {
        Write-Host "Cluster is ready!" -ForegroundColor Green
    } else {
        Write-Host "Cluster did not become ready in time. You might need to recreate it with -ForceRecreate." -ForegroundColor Yellow
    }
} else {
    Write-Host "Cluster 'smu' does not exist. Creating it..." -ForegroundColor Yellow
    kind create cluster --name smu --config kind-config.yaml
    kubectl config use-context kind-smu
}
