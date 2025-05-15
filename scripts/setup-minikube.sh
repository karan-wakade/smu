#!/bin/bash
set -e

# Start Minikube if not running
if ! minikube status | grep -q "Running"; then
  echo "Starting Minikube..."
  minikube start --driver=virtualbox --memory=4096 --cpus=2
else
  echo "Minikube is already running"
fi

# Enable ingress addon
echo "Enabling ingress addon..."
minikube addons enable ingress

# Set up monitoring
echo "Setting up monitoring..."
kubectl apply -f k8s/monitoring/prometheus.yaml
kubectl apply -f k8s/monitoring/grafana.yaml

# Deploy application
echo "Deploying application..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

# Wait for deployments
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/smu-app
kubectl rollout status deployment/grafana -n monitoring
kubectl rollout status deployment/prometheus -n monitoring

# Add hosts entry
echo "Minikube IP: $(minikube ip)"
echo "Add the following entry to your /etc/hosts file:"
echo "$(minikube ip) smu.local"

# Show service URLs
echo "Grafana URL: http://$(minikube ip):$(kubectl get svc grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')"
echo "Application URL: http://smu.local"