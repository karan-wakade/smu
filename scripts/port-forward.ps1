param (
    [string]$Namespace = "default",
    [string]$Environment = "staging",
    [int]$LocalPort = 8080
)

$resourceName = "$Environment-rollout-service"

Write-Host "Setting up port forwarding for $resourceName in namespace $Namespace..." -ForegroundColor Green
Write-Host "Application will be available at http://localhost:$LocalPort" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop port forwarding" -ForegroundColor Yellow

kubectl port-forward service/$resourceName $LocalPort:80 -n $Namespace
