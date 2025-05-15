# Migration script from Minikube to Kind
param (
    [switch]$Skip_Secrets_Migration = $false,
    [switch]$Skip_Monitoring = $false
)

Write-Host "=== SMU Migration from Minikube to Kind ===" -ForegroundColor Cyan
Write-Host "Started at: $(Get-Date)" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check requirements
Write-Host "Step 1: Checking requirements..." -ForegroundColor Green

# Check if Kind is installed
if (-not (Get-Command "kind" -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Kind is not installed. Please install it with: choco install kind" -ForegroundColor Red
    exit 1
}

# Check if Docker is running
try {
    docker version | Out-Null
} catch {
    Write-Host "ERROR: Docker is not running. Please start Docker Desktop first." -ForegroundColor Red
    exit 1
}

# Check if helm is installed
if (-not (Get-Command "helm" -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: Helm is not installed. Monitoring setup will be skipped." -ForegroundColor Yellow
    $Skip_Monitoring = $true
}

Write-Host "All requirements satisfied!" -ForegroundColor Green
Write-Host ""

# Step 2: Create Kind cluster
Write-Host "Step 2: Creating Kind cluster..." -ForegroundColor Green

# Create kind-config.yaml if it doesn't exist
$kindConfigPath = "kind-config.yaml"
if (-not (Test-Path $kindConfigPath)) {
    Write-Host "Creating Kind configuration file..." -ForegroundColor Yellow
    @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 3000
    hostPort: 3000
    protocol: TCP
  - containerPort: 9090
    hostPort: 9090
    protocol: TCP
- role: worker
"@ | Out-File -FilePath $kindConfigPath -Encoding utf8
}

# Check if cluster already exists
$clusterExists = kind get clusters | Where-Object { $_ -eq "smu" }
if ($clusterExists) {
    $answer = Read-Host "Kind cluster 'smu' already exists. Delete and recreate? (y/N)"
    if ($answer -eq "y" -or $answer -eq "Y") {
        Write-Host "Deleting existing cluster..." -ForegroundColor Yellow
        kind delete cluster --name smu
        $clusterExists = $false
    } else {
        Write-Host "Using existing cluster." -ForegroundColor Yellow
    }
}

# Create cluster if it doesn't exist
if (-not $clusterExists) {
    Write-Host "Creating Kind cluster 'smu'..." -ForegroundColor Green
    kind create cluster --name smu --config $kindConfigPath
    
    # Install ingress-nginx
    Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Green
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    # Wait for ingress to be ready
    Write-Host "Waiting for NGINX Ingress Controller to be ready..." -ForegroundColor Yellow
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
} else {
    # Just ensure we're using the right context
    kubectl config use-context kind-smu
}

Write-Host "Kind cluster is ready!" -ForegroundColor Green
Write-Host ""

# Step 3: Migrate secrets if needed
if (-not $Skip_Secrets_Migration) {
    Write-Host "Step 3: Migrating secrets from Minikube..." -ForegroundColor Green
    
    # Check if Minikube is running
    $minikubeRunning = $false
    try {
        $minikubeStatus = minikube status
        if ($minikubeStatus -match "host: Running") {
            $minikubeRunning = $true
        }
    } catch {
        Write-Host "Minikube not running or not found. Skipping secrets migration." -ForegroundColor Yellow
    }
    
    if ($minikubeRunning) {
        # Get all secrets from default namespace
        $tempDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        
        Write-Host "Exporting secrets from Minikube..." -ForegroundColor Yellow
        kubectl --context minikube get secrets -o json | ConvertFrom-Json | ForEach-Object {
            if ($_.items) {
                foreach ($item in $_.items) {
                    # Skip default-token secrets
                    if ($item.metadata.name -notmatch "^default-token-") {
                        $name = $item.metadata.name
                        Write-Host "  Exporting secret: $name" -ForegroundColor Yellow
                        
                        # Remove server-specific fields
                        $item.PSObject.Properties.Remove("status")
                        if ($item.metadata.PSObject.Properties["creationTimestamp"]) {
                            $item.metadata.PSObject.Properties.Remove("creationTimestamp")
                        }
                        if ($item.metadata.PSObject.Properties["resourceVersion"]) {
                            $item.metadata.PSObject.Properties.Remove("resourceVersion")
                        }
                        if ($item.metadata.PSObject.Properties["uid"]) {
                            $item.metadata.PSObject.Properties.Remove("uid")
                        }
                        
                        # Save to temp file
                        $item | ConvertTo-Json -Depth 10 | Out-File -FilePath "$tempDir\$name.json" -Encoding utf8
                    }
                }
            }
        }
        
        # Apply secrets to Kind
        Write-Host "Importing secrets to Kind..." -ForegroundColor Yellow
        Get-ChildItem -Path $tempDir -Filter "*.json" | ForEach-Object {
            $secretName = $_.BaseName
            Write-Host "  Importing secret: $secretName" -ForegroundColor Yellow
            kubectl --context kind-smu apply -f $_.FullName
        }
        
        # Clean up
        Remove-Item -Path $tempDir -Recurse -Force
        
        Write-Host "Secrets migration completed!" -ForegroundColor Green
    } else {
        Write-Host "Creating a template .env.local file for manual configuration..." -ForegroundColor Yellow
        
        @"
# SMU Application Environment Variables
# Replace these with your actual values

# API Keys
API_KEY=your_api_key_here

# Database
DB_HOST=localhost
DB_USER=smu_user
DB_PASSWORD=changeme
DB_NAME=smu_db

# App Settings
NODE_ENV=development
"@ | Out-File -FilePath ".env.local" -Encoding utf8
        
        Write-Host "Created .env.local template. Please update with your actual values." -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Step 4: Set up monitoring
if (-not $Skip_Monitoring) {
    Write-Host "Step 4: Setting up monitoring..." -ForegroundColor Green
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Helm repos
    Write-Host "Adding Helm repositories..." -ForegroundColor Yellow
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus stack
    Write-Host "Installing Prometheus and Grafana..." -ForegroundColor Yellow
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack `
        --namespace monitoring `
        --set grafana.enabled=true `
        --set prometheus.service.type=ClusterIP `
        --set grafana.service.type=ClusterIP
    
    # Wait for Grafana to be ready
    Write-Host "Waiting for Grafana to be ready..." -ForegroundColor Yellow
    
    $ready = $false
    $attempts = 0
    $maxAttempts = 10
    
    while (-not $ready -and $attempts -lt $maxAttempts) {
        $attempts++
        Write-Host "  Checking Grafana status (attempt $attempts/$maxAttempts)..." -ForegroundColor Yellow
        
        $podsReady = kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath="{.items[0].status.phase}" 2>$null
        if ($podsReady -eq "Running") {
            $ready = $true
        } else {
            Start-Sleep -Seconds 10
        }
    }
    
    if ($ready) {
        # Get Grafana admin password
        $encodedPassword = kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}"
        $adminPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPassword))
        
        Write-Host "Monitoring setup complete!" -ForegroundColor Green
        Write-Host "Grafana is available at: http://localhost:3000" -ForegroundColor Green
        Write-Host "Username: admin" -ForegroundColor Green
        Write-Host "Password: $adminPassword" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Grafana did not become ready in time. You can check its status later." -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Step 5: Create helpful scripts
Write-Host "Step 5: Creating helper scripts..." -ForegroundColor Green

# Create scripts directory if it doesn't exist
if (-not (Test-Path "scripts")) {
    New-Item -ItemType Directory -Path "scripts" | Out-Null
}

# Create apply-secrets script
@"
param (
    [string]`$Namespace = "default",
    [string]`$EnvFile = ".env.local"
)

# Check if env file exists
if (-not (Test-Path `$EnvFile)) {
    Write-Host "Environment file `$EnvFile not found!" -ForegroundColor Red
    exit 1
}

# Read env file and create Kubernetes secret
Write-Host "Creating Kubernetes secret from `$EnvFile..." -ForegroundColor Green

# Create a temporary file for the secret
`$tempFile = [System.IO.Path]::GetTempFileName()

@"
apiVersion: v1
kind: Secret
metadata:
  name: smu-config
  namespace: `$Namespace
type: Opaque
data:
"@ | Out-File -FilePath `$tempFile

# Process each line in the env file
Get-Content `$EnvFile | Where-Object { `$_ -match "^\s*([^#][^=]+)=(.*)$" } | ForEach-Object {
    `$key = `$matches[1].Trim()
    `$value = `$matches[2]
    
    # Convert value to base64 for Kubernetes secret
    `$base64Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(`$value))
    
    # Add to secret file
    "  `$key`: `$base64Value" | Out-File -FilePath `$tempFile -Append
}

# Apply secret to cluster
kubectl apply -f `$tempFile

# Clean up temp file
Remove-Item `$tempFile

Write-Host "Secret 'smu-config' applied to namespace '`$Namespace'" -ForegroundColor Green
"@ | Out-File -FilePath "scripts\apply-secrets.ps1" -Encoding utf8

# Create port-forward script
@"
param (
    [string]`$Namespace = "default",
    [string]`$Environment = "staging",
    [int]`$LocalPort = 8080
)

`$resourceName = "`$Environment-rollout-service"

Write-Host "Setting up port forwarding for `$resourceName in namespace `$Namespace..." -ForegroundColor Green
Write-Host "Application will be available at http://localhost:`$LocalPort" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop port forwarding" -ForegroundColor Yellow

kubectl port-forward service/`$resourceName `$LocalPort:80 -n `$Namespace
"@ | Out-File -FilePath "scripts\port-forward.ps1" -Encoding utf8

# Create deploy script
@"
param (
    [string]`$Namespace = "default",
    [string]`$Environment = "staging"
)

# Ensure namespace exists
kubectl create namespace `$Namespace --dry-run=client -o yaml | kubectl apply -f -

# Build and load the Docker image into Kind
Write-Host "Building Docker image..." -ForegroundColor Green
docker build -t ghcr.io/karan-wakade/smu:latest .

Write-Host "Loading image into Kind cluster..." -ForegroundColor Green
kind load docker-image ghcr.io/karan-wakade/smu:latest --name smu

# Apply secrets
Write-Host "Applying secrets..." -ForegroundColor Green
./scripts/apply-secrets.ps1 -Namespace `$Namespace

# Apply Kubernetes resources
Write-Host "Deploying application resources for environment: `$Environment..." -ForegroundColor Green
kubectl apply -k kubernetes/overlays/`$Environment -n `$Namespace

# Wait for deployment to be ready
`$deploymentName = "`$Environment-rollout"
Write-Host "Waiting for deployment `$deploymentName to be ready..." -ForegroundColor Yellow

# Try a few times in case it times out
`$maxAttempts = 3
`$success = `$false

for (`$attempt = 1; `$attempt -le `$maxAttempts; `$attempt++) {
    try {
        Write-Host "Attempt `$attempt of `$maxAttempts..." -ForegroundColor Yellow
        kubectl rollout status deployment/`$deploymentName -n `$Namespace --timeout=60s
        `$success = `$true
        break
    } catch {
        Write-Host "Deployment status check timed out, checking deployment status..." -ForegroundColor Yellow
        kubectl get deployment `$deploymentName -n `$Namespace
    }
}

# Get service information
`$serviceIP = kubectl get service "`$deploymentName-service" -n `$Namespace -o jsonpath='{.spec.clusterIP}'
`$servicePort = kubectl get service "`$deploymentName-service" -n `$Namespace -o jsonpath='{.spec.ports[0].port}'

Write-Host "Application deployed successfully!" -ForegroundColor Green
Write-Host "Service available at: http://`$serviceIP:`$servicePort within the cluster" -ForegroundColor Green
Write-Host "To access locally, run: ./scripts/port-forward.ps1 -Environment `$Environment -LocalPort 8080" -ForegroundColor Green
"@ | Out-File -FilePath "scripts\deploy-app.ps1" -Encoding utf8

# Create monitoring dashboard script
@"
param (
    [string]`$Namespace = "monitoring"
)

# Start port-forwarding for Grafana
Write-Host "Setting up port forwarding for Grafana..." -ForegroundColor Green
`$grafanaPod = kubectl get pods -n `$Namespace -l "app.kubernetes.io/name=grafana" -o name

if (-not `$grafanaPod) {
    Write-Host "ERROR: Grafana pod not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Grafana will be available at http://localhost:3000" -ForegroundColor Green
Write-Host "Username: admin" -ForegroundColor Green

# Get password
`$encodedPassword = kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}"
`$adminPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(`$encodedPassword))
Write-Host "Password: `$adminPassword" -ForegroundColor Green

Write-Host "Press Ctrl+C to stop port forwarding" -ForegroundColor Yellow
kubectl port-forward -n `$Namespace `$grafanaPod 3000:3000
"@ | Out-File -FilePath "scripts\grafana-dashboard.ps1" -Encoding utf8

# Create restart script
@"
param (
    [switch]`$ForceRecreate = `$false
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
`$clusterExists = kind get clusters | Where-Object { `$_ -eq "smu" }
if (`$clusterExists -and `$ForceRecreate) {
    Write-Host "Deleting existing cluster..." -ForegroundColor Yellow
    kind delete cluster --name smu
    kind create cluster --name smu --config kind-config.yaml
    
    # Set current context to the new cluster
    kubectl config use-context kind-smu
    
    # Install ingress-nginx
    Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Green
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    
    Write-Host "Cluster has been recreated. Please run scripts/deploy-app.ps1 to redeploy your application." -ForegroundColor Green
} elseif (`$clusterExists) {
    Write-Host "Restarting Docker container for Kind cluster..." -ForegroundColor Yellow
    docker restart kind-control-plane kind-worker
    
    # Wait for cluster to be ready
    Write-Host "Waiting for cluster to be ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Set current context
    kubectl config use-context kind-smu
    
    # Wait for node to be ready
    `$ready = `$false
    `$attempts = 0
    `$maxAttempts = 12
    
    while (-not `$ready -and `$attempts -lt `$maxAttempts) {
        `$attempts++
        `$nodeStatus = kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
        
        if (`$nodeStatus -eq "True") {
            `$ready = `$true
        } else {
            Write-Host "Waiting for nodes to be ready (attempt `$attempts/`$maxAttempts)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }
    
    if (`$ready) {
        Write-Host "Cluster is ready!" -ForegroundColor Green
    } else {
        Write-Host "Cluster did not become ready in time. You might need to recreate it with -ForceRecreate." -ForegroundColor Yellow
    }
} else {
    Write-Host "Cluster 'smu' does not exist. Creating it..." -ForegroundColor Yellow
    kind create cluster --name smu --config kind-config.yaml
    kubectl config use-context kind-smu
}
"@ | Out-File -FilePath "scripts\restart-cluster.ps1" -Encoding utf8

Write-Host "Created helper scripts in the 'scripts' directory:" -ForegroundColor Green
Write-Host "  - apply-secrets.ps1: Apply secrets from .env.local file" -ForegroundColor Green
Write-Host "  - port-forward.ps1: Set up port forwarding to access your app" -ForegroundColor Green
Write-Host "  - deploy-app.ps1: Deploy your application" -ForegroundColor Green
Write-Host "  - grafana-dashboard.ps1: Access Grafana dashboards" -ForegroundColor Green
Write-Host "  - restart-cluster.ps1: Restart or recreate the Kind cluster" -ForegroundColor Green
Write-Host ""

# Step 6: Update Kubernetes manifests if needed
Write-Host "Step 6: Checking Kubernetes manifests..." -ForegroundColor Green

# Create base directory structure if it doesn't exist
$kubernetesBasePath = "kubernetes\base"
if (-not (Test-Path $kubernetesBasePath)) {
    Write-Host "Creating Kubernetes base directory structure..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $kubernetesBasePath -Force | Out-Null
    
    # Create base deployment
    @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smu-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: smu
  template:
    metadata:
      labels:
        app: smu
    spec:
      containers:
      - name: smu-container
        image: ghcr.io/karan-wakade/smu:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
        envFrom:
        - secretRef:
            name: smu-config
"@ | Out-File -FilePath "$kubernetesBasePath\deployment.yaml" -Encoding utf8
    
    # Create base service
    @"
apiVersion: v1
kind: Service
metadata:
  name: smu-service
spec:
  selector:
    app: smu
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
"@ | Out-File -FilePath "$kubernetesBasePath\service.yaml" -Encoding utf8
    
    # Create base kustomization
    @"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml
"@ | Out-File -FilePath "$kubernetesBasePath\kustomization.yaml" -Encoding utf8
}

# Create staging overlay if it doesn't exist
$kubernetesOverlayPath = "kubernetes\overlays\staging"
if (-not (Test-Path $kubernetesOverlayPath)) {
    Write-Host "Creating Kubernetes staging overlay..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $kubernetesOverlayPath -Force | Out-Null
    
    # Create staging kustomization
    @"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

namePrefix: staging-

patches:
- path: deployment-patch.yaml
"@ | Out-File -FilePath "$kubernetesOverlayPath\kustomization.yaml" -Encoding utf8
    
    # Create staging deployment patch
    @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smu-app
spec:
  replicas: 1
  template:
    metadata:
      labels:
        environment: staging
    spec:
      containers:
      - name: smu-container
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
"@ | Out-File -FilePath "$kubernetesOverlayPath\deployment-patch.yaml" -Encoding utf8
}

Write-Host "Kubernetes manifests are ready!" -ForegroundColor Green
Write-Host ""

# Final instructions
Write-Host "=== Migration Complete! ===" -ForegroundColor Cyan
Write-Host "Your Kind cluster is now ready to use." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Update .env.local with your application secrets" -ForegroundColor Yellow
Write-Host "2. Deploy your application: ./scripts/deploy-app.ps1" -ForegroundColor Yellow
Write-Host "3. Access your application: ./scripts/port-forward.ps1" -ForegroundColor Yellow
Write-Host "4. View Grafana dashboards: ./scripts/grafana-dashboard.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "If you need to restart your cluster later: ./scripts/restart-cluster.ps1" -ForegroundColor Yellow