# Make sure these variables are set in your environment
# $env:GHCR_PAT = "your_personal_access_token"
# $env:KUBE_CONFIG = "your_kubeconfig_content"

# Login to GitHub Container Registry
Write-Host "Logging in to GitHub Container Registry..." -ForegroundColor Cyan
$env:GHCR_PAT | docker login ghcr.io -u karan-wakade --password-stdin

# Create kubeconfig for kubectl to use
Write-Host "Setting up kubectl configuration..." -ForegroundColor Cyan
$kubePath = "$env:USERPROFILE\.kube"
if (-not (Test-Path $kubePath)) {
    New-Item -ItemType Directory -Path $kubePath | Out-Null
}

if ($env:KUBE_CONFIG) {
    # Check if KUBE_CONFIG is base64 encoded
    try {
        $decodedConfig = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($env:KUBE_CONFIG))
        $decodedConfig | Out-File -FilePath "$kubePath\config" -Encoding utf8
    } catch {
        # If not base64 encoded, write directly
        $env:KUBE_CONFIG | Out-File -FilePath "$kubePath\config" -Encoding utf8
    }
} else {
    Write-Host "KUBE_CONFIG environment variable not set!" -ForegroundColor Red
    exit 1
}

# Now you can apply your Kubernetes configurations
Write-Host "Starting deployment process..." -ForegroundColor Cyan
kubectl apply -f .\k8s\base\namespace.yaml
kubectl apply -f .\k8s\monitoring\
kubectl apply -f .\k8s\auto-tuning\
kubectl apply -f .\k8s\argo-rollouts\

# Monitor deployment
Write-Host "Monitoring rollout..." -ForegroundColor Cyan
kubectl argo rollouts get rollout smu-frontend -n smu-system