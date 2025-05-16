# Ensure Minikube is running
if (-not (minikube status | Select-String -Pattern "Running")) {
    Write-Host "Starting Minikube..."
    minikube start --driver=docker --memory=4096 --cpus=2
} else {
    Write-Host "Minikube is already running"
}

# Enable ingress addon
Write-Host "Enabling ingress addon..."
minikube addons enable ingress

# Set up monitoring
Write-Host "Setting up monitoring..."
kubectl apply -f k8s/monitoring/prometheus.yaml
kubectl apply -f k8s/monitoring/grafana.yaml

# Deploy application
Write-Host "Deploying application..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# Wait for deployments
Write-Host "Waiting for deployments to be ready..."
kubectl rollout status deployment/smu-app
kubectl rollout status deployment/grafana -n monitoring
kubectl rollout status deployment/prometheus -n monitoring

# Add hosts entry
$minikubeIP = minikube ip
Write-Host "Minikube IP: $minikubeIP"
Write-Host "Add the following entry to your hosts file:"
Write-Host "$minikubeIP smu.local"

# Show service URLs
$grafanaPort = kubectl get svc grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}'
Write-Host "Grafana URL: http://${minikubeIP}:${grafanaPort}"
Write-Host "Application URL: http://smu.local"