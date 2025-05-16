# Exit on error
$ErrorActionPreference = "Stop"

# Usage information
param (
    [Parameter(Mandatory = $true)]
    [int]$Percentage
)

# Validate percentage input
if ($Percentage -lt 0 -or $Percentage -gt 100) {
    Write-Host "Usage: ./deploy-canary.ps1 -Percentage <0-100>"
    Write-Host "Example: ./deploy-canary.ps1 -Percentage 20"
    exit 1
}

# Update canary percentage in the deployment file
Write-Host "Updating canary percentage to $Percentage%..."
(Get-Content k8s/canary/deployment.yaml) -replace "canary_percentage:.*", "canary_percentage: $Percentage" | Set-Content k8s/canary/deployment.yaml

# Apply canary deployment
Write-Host "Deploying canary with $Percentage% traffic..."
kubectl apply -f k8s/canary/deployment.yaml

# Wait for deployment to be ready
Write-Host "Waiting for canary deployment to be ready..."
kubectl rollout status deployment/smu-app-canary

# Display monitoring information
$minikubeIP = minikube ip
$grafanaPort = kubectl get svc grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}'
Write-Host "Canary deployment complete."
Write-Host "Monitor in Grafana: http://${minikubeIP}:${grafanaPort}"