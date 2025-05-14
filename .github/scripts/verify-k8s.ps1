# Copy the kubeconfig
Copy-Item -Path ".github\kubeconfig\config" -Destination "$env:TEMP\k8s-config" -Force
$env:KUBECONFIG = "$env:TEMP\k8s-config"

# Retry mechanism for connection
$maxRetries = 3
$retryCount = 0
$success = $false

while (-not $success -and $retryCount -lt $maxRetries) {
  try {
    $retryCount++
    Write-Host "Connection attempt $retryCount of $maxRetries..."
    kubectl get nodes --request-timeout=60s
    $success = $true
    Write-Host "✅ Connection successful!"
  } catch {
    Write-Host "❌ Connection attempt $retryCount failed: $_"
    Start-Sleep -Seconds 5
  }
}

if (-not $success) {
  Write-Host "❌ All connection attempts failed. Aborting."
  exit 1
}