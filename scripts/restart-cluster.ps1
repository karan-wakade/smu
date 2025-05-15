param (
    [switch]$ForceRecreate = $false
)

Write-Host "=== Kind Cluster Manager ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "User: $env:USERNAME" -ForegroundColor Cyan
Write-Host ""

# Check if Kind is installed
if (-not (Get-Command "kind" -ErrorAction SilentlyContinue)) {
    Write-Host "Kind is not installed. Please install it first with: choco install kind" -ForegroundColor Red
    exit 1
}

# Check if Docker is running
try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker info command failed"
    }
    Write-Host "✓ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

# Check if cluster exists in Kind
$clusterExists = kind get clusters | Where-Object { $_ -eq "smu" }

# Check if the containers exist in Docker
$controlPlaneExists = $false
$workerExists = $false

try {
    $controlPlaneExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq "kind-control-plane" }
    $workerExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq "kind-worker" }
} catch {
    Write-Host "Warning: Couldn't check for Kind containers in Docker" -ForegroundColor Yellow
}

# Handle cluster recreation if forced or needed
if (($clusterExists -and $ForceRecreate) -or ($clusterExists -and (-not $controlPlaneExists -or -not $workerExists))) {
    Write-Host "Deleting existing cluster..." -ForegroundColor Yellow
    kind delete cluster --name smu
    $clusterExists = $false
}

# Create cluster if it doesn't exist
if (-not $clusterExists) {
    Write-Host "Creating new Kind cluster 'smu'..." -ForegroundColor Green
    
    # Check if kind-config.yaml exists
    if (-not (Test-Path "kind-config.yaml")) {
        Write-Host "Creating Kind configuration file..." -ForegroundColor Yellow
        
        # Create config line by line to avoid PowerShell string formatting issues
        "kind: Cluster" | Out-File -FilePath "kind-config.yaml" -Encoding utf8
        "apiVersion: kind.x-k8s.io/v1alpha4" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "nodes:" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "- role: control-plane" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "  extraPortMappings:" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "  - containerPort: 80" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "    hostPort: 80" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "  - containerPort: 443" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "    hostPort: 443" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
        "- role: worker" | Out-File -FilePath "kind-config.yaml" -Append -Encoding utf8
    }
    
    # Create the cluster with a timeout
    kind create cluster --name smu --config kind-config.yaml --wait 3m
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error creating cluster. Please check Docker and try again." -ForegroundColor Red
        exit 1
    }
    
    # Set current context to the new cluster
    kubectl config use-context kind-smu
    
    # Install ingress-nginx
    Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Green
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    Write-Host "Cluster has been created. Run scripts/deploy-app.ps1 to deploy your application." -ForegroundColor Green
    exit 0
} 
# Restart existing containers if needed
elseif ($controlPlaneExists -and $workerExists) {
    Write-Host "Restarting Docker containers for Kind cluster..." -ForegroundColor Yellow
    
    try {
        # Check container status first
        $controlPlaneStatus = docker inspect --format='{{.State.Running}}' kind-control-plane 2>$null
        $workerStatus = docker inspect --format='{{.State.Running}}' kind-worker 2>$null
        
        # Only restart if they exist and are not running
        if ($controlPlaneStatus -eq "false") {
            docker start kind-control-plane
            Write-Host "Started control plane container" -ForegroundColor Green
        } elseif ($controlPlaneStatus -eq "true") {
            Write-Host "Control plane container is already running" -ForegroundColor Green
        }
        
        if ($workerStatus -eq "false") {
            docker start kind-worker
            Write-Host "Started worker container" -ForegroundColor Green
        } elseif ($workerStatus -eq "true") {
            Write-Host "Worker container is already running" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error restarting containers: $_" -ForegroundColor Red
        Write-Host "Recreating the cluster might be needed. Run with -ForceRecreate" -ForegroundColor Yellow
    }
    
    # Set current context
    kubectl config use-context kind-smu
    
    # Wait for node to be ready with proper JsonPath syntax
    $ready = $false
    $attempts = 0
    $maxAttempts = 12
    
    Write-Host "Waiting for nodes to be ready..." -ForegroundColor Yellow
    
    while (-not $ready -and $attempts -lt $maxAttempts) {
        $attempts++
        
        try {
            # Use proper quotes around "Ready" in the JsonPath expression
            $nodeStatus = kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
            
            if ($nodeStatus -eq "True") {
                $ready = $true
                Write-Host "✓ Nodes are ready!" -ForegroundColor Green
                break
            } else {
                Write-Host "Waiting for nodes to be ready (attempt $attempts/$maxAttempts)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        } catch {
            Write-Host "Error checking node status: $_" -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
    }
    
    if ($ready) {
        Write-Host "✓ Cluster is ready!" -ForegroundColor Green
        
        # Show some basic information about the cluster
        Write-Host ""
        Write-Host "Cluster Information:" -ForegroundColor Cyan
        Write-Host "-------------------" -ForegroundColor Cyan
        kubectl cluster-info
        Write-Host ""
        Write-Host "Node Status:" -ForegroundColor Cyan
        Write-Host "-------------------" -ForegroundColor Cyan
        kubectl get nodes
    } else {
        Write-Host "✗ Cluster did not become ready in time." -ForegroundColor Red
        Write-Host "You should recreate it with: ./scripts/restart-cluster.ps1 -ForceRecreate" -ForegroundColor Yellow
    }
} else {
    # This is a weird state where Kind thinks the cluster exists but Docker doesn't have the containers
    Write-Host "Cluster 'smu' exists in Kind but containers are missing in Docker." -ForegroundColor Red
    Write-Host "This indicates a corrupted state. Please run with -ForceRecreate flag to rebuild." -ForegroundColor Yellow
    exit 1
}