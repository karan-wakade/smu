# Switch to minikube context
kubectl config use-context minikube

# Get server URL
$minikubeServer = kubectl config view --minify --raw -o jsonpath="{.clusters[0].cluster.server}"
Write-Host "Minikube Server: $minikubeServer"

# Create kubeconfig directory if it doesn't exist
New-Item -Path .github\kubeconfig -ItemType Directory -Force | Out-Null

# Export the current minikube context to a separate file
Write-Host "Exporting minikube kubeconfig..."
kubectl config view --minify --flatten > .github\kubeconfig\config

# Check if the file was created successfully
if (Test-Path .github\kubeconfig\config) {
    Write-Host "✅ Successfully created kubeconfig file"
    
    # Test the config works
    $env:KUBECONFIG = "$(Get-Location)\.github\kubeconfig\config"
    $nodes = kubectl get nodes
    Write-Host "Cluster nodes:"
    Write-Host $nodes
} else {
    Write-Host "❌ Failed to create kubeconfig file"
}
