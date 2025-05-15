param (
    [string]$Namespace = "monitoring"
)

# Start port-forwarding for Grafana
Write-Host "Setting up port forwarding for Grafana..." -ForegroundColor Green
$grafanaPod = kubectl get pods -n $Namespace -l "app.kubernetes.io/name=grafana" -o name

if (-not $grafanaPod) {
    Write-Host "ERROR: Grafana pod not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Grafana will be available at http://localhost:3000" -ForegroundColor Green
Write-Host "Username: admin" -ForegroundColor Green

# Get password
$encodedPassword = kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}"
$adminPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPassword))
Write-Host "Password: $adminPassword" -ForegroundColor Green

Write-Host "Press Ctrl+C to stop port forwarding" -ForegroundColor Yellow
kubectl port-forward -n $Namespace $grafanaPod 3000:3000
