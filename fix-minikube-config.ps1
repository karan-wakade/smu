# First ensure minikube is running properly
$minikubeStatus = minikube status
if ($minikubeStatus -match "apiserver: Stopped") {
    Write-Host "Minikube API server is not running, starting it..."
    minikube start
    Start-Sleep -Seconds 10
}

# Get the real minikube IP instead of localhost
$minikubeIP = minikube ip
Write-Host "Minikube IP: $minikubeIP"

# Get the API server port 
$serverUrl = kubectl config view --minify -o jsonpath="{.clusters[0].cluster.server}"
$port = if ($serverUrl -match ":(\d+)$") { $Matches[1] } else { "8443" }
Write-Host "API Server Port: $port"

# Create directory if it doesn't exist
New-Item -Path .github\kubeconfig -ItemType Directory -Force | Out-Null

# Get the raw kubeconfig with certificates
$rawConfig = kubectl config view --minify --flatten

# Replace localhost/127.0.0.1 with the real minikube IP
$updatedConfig = $rawConfig -replace 'server: https://(localhost|127.0.0.1):\d+', "server: https://$minikubeIP:$port"

# Write the updated config
$updatedConfig | Set-Content -Path .github\kubeconfig\config

# Test the new config
$env:KUBECONFIG = "$(Get-Location)\.github\kubeconfig\config"
Write-Host "Testing config with real IP..."

try {
    $nodes = kubectl get nodes --request-timeout=30s
    Write-Host "✅ Connection successful: $nodes"
} catch {
    Write-Host "❌ Connection test failed: $_"
}
