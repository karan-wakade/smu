import kubernetes
import time
import requests
import pandas as pd
from datetime import datetime
from model import DeploymentTuner

# Initialize the Kubernetes client
kubernetes.config.load_incluster_config()
k8s_apps_v1 = kubernetes.client.CustomObjectsApi()

# Initialize our model
tuner = DeploymentTuner()

def get_current_metrics():
    """Get current system metrics from Prometheus"""
    prom_url = "http://prometheus:9090/api/v1/query"
    
    # Get traffic level (requests per second)
    response = requests.get(prom_url, params={
        'query': 'sum(rate(http_requests_total{app="frontend"}[5m]))'
    })
    traffic_level = float(response.json()['data']['result'][0]['value'][1])
    
    # Get error rate from previous deployment
    response = requests.get(prom_url, params={
        'query': 'sum(rate(http_requests_total{app="frontend",status=~"5.."}[1h])) / sum(rate(http_requests_total{app="frontend"}[1h]))'
    })
    error_rate = float(response.json()['data']['result'][0]['value'][1]) if response.json()['data']['result'] else 0
    
    now = datetime.now()
    
    return {
        'traffic_level': traffic_level,
        'error_rate_prev': error_rate,
        'deploy_time': now.hour,
        'deploy_day': now.weekday()
    }

def update_rollout_steps(rollout_name, namespace, steps):
    """Update the canary steps in an Argo Rollout"""
    rollout = k8s_apps_v1.get_namespaced_custom_object(
        group="argoproj.io",
        version="v1alpha1",
        namespace=namespace,
        plural="rollouts",
        name=rollout_name
    )
    
    # Construct new canary steps
    new_steps = []
    for weight in steps:
        new_steps.append({"setWeight": weight})
        new_steps.append({"pause": {"duration": "2m"}})
    
    # Update the rollout
    rollout['spec']['strategy']['canary']['steps'] = new_steps
    
    k8s_apps_v1.patch_namespaced_custom_object(
        group="argoproj.io",
        version="v1alpha1",
        namespace=namespace,
        plural="rollouts",
        name=rollout_name,
        body=rollout
    )
    
    print(f"Updated rollout {rollout_name} with new canary steps: {steps}")

def collect_deployment_data():
    """Collect deployment data for model training"""
    prom_url = "http://prometheus:9090/api/v1/query"
    
    # Get deployment success rate
    response = requests.get(prom_url, params={
        'query': 'avg_over_time(deployment_success_gauge[30d])'
    })
    
    results = response.json()['data']['result']
    
    data = []
    for result in results:
        metadata = result['metric']
        value = float(result['value'][1])
        
        data.append({
            'deployment_id': metadata.get('deployment_id', 'unknown'),
            'traffic_level': float(metadata.get('traffic_level', 0)),
            'error_rate_prev': float(metadata.get('error_rate_prev', 0)),
            'deploy_time': int(metadata.get('deploy_time', 0)),
            'deploy_day': int(metadata.get('deploy_day', 0)),
            'canary_increment': int(metadata.get('canary_increment', 10)),
            'success_rate': value
        })
    
    return pd.DataFrame(data)

def main_loop():
    while True:
        try:
            # Train model with historical data
            deployment_data = collect_deployment_data()
            if not deployment_data.empty:
                tuner.train(deployment_data)
            
            # Get current metrics
            metrics = get_current_metrics()
            
            # Get recommended canary steps
            steps = tuner.recommend_canary_steps(metrics)
            
            # Update the frontend rollout
            update_rollout_steps("frontend", "default", steps)
            
        except Exception as e:
            print(f"Error in auto-tuning controller: {e}")
            
        # Run every 6 hours
        time.sleep(6 * 60 * 60)

if __name__ == "__main__":
    main_loop()