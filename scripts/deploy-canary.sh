#!/bin/bash
set -e

# Usage information
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <percentage>"
    echo "Example: $0 20"
    exit 1
fi

PERCENTAGE=$1

# Update canary percentage
sed -i "s/canary_percentage:.*/canary_percentage: $PERCENTAGE/" k8s/canary/deployment.yaml

# Apply canary deployment
echo "Deploying canary with $PERCENTAGE% traffic..."
kubectl apply -f k8s/canary/deployment.yaml

# Wait for deployment
echo "Waiting for canary deployment to be ready..."
kubectl rollout status deployment/smu-app-canary

echo "Canary deployment complete."
echo "Monitor in Grafana: http://$(minikube ip):$(kubectl get svc grafana -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')"