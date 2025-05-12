import kubernetes
import time
import requests
import pandas as pd
from datetime import datetime
import logging
import json
from model import DeploymentTuner
from data_manager import DeploymentDataManager

# Set up logging
logging.basicConfig(level=logging.INFO,
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("auto-tuner")

# Initialize Kubernetes client
kubernetes.config.load_incluster_config()
k8s_apps_v1 = kubernetes.client.CustomObjectsApi()

# Initialize our model and data manager
tuner = DeploymentTuner()
data_manager = DeploymentDataManager()

def get_current_metrics():
    """Get current system metrics from Prometheus"""
    logger.info("Fetching current metrics from Prometheus")
    prom_url = "http://prometheus-server.monitoring:9090/api/v1/query"
    
    metrics = {}
    
    try:
        # Get traffic level (requests per second)
        response = requests.get(prom_url, params={
            'query': 'sum(rate(http_requests_total{app="frontend"}[5m]))'
        })
        if response.status_code == 200 and response.json()['data']['result']:
            metrics['traffic_level'] = float(response.json()['data']['result'][0]['value'][1])
        else:
            metrics['traffic_level'] = 0
        
        # Get error rate from previous deployment
        response = requests.get(prom_url, params={
            'query': 'sum(rate(http_requests_total{app="frontend",status=~"5.."}[1h])) / sum(rate(http_requests_total{app="frontend"}[1h]))'
        })
        if response.status_code == 200 and response.json()['data']['result']:
            metrics['error_rate_prev'] = float(response.json()['data']['result'][0]['value'][1])
        else:
            metrics['error_rate_prev'] = 0
        
        now = datetime.now()
        metrics['deploy_time'] = now.hour
        metrics['deploy_day'] = now.weekday()
        
        logger.info(f"Current metrics: {metrics}")
        return metrics
        
    except Exception as e:
        logger.error(f"Error fetching metrics: {e}")
        # Return default metrics
        return {
            'traffic_level': 0,
            'error_rate_prev': 0,
            'deploy_time': datetime.now().hour,
            'deploy_day': datetime.now().weekday()
        }

def update_rollout_steps(rollout_name, namespace, steps):
    """Update the canary steps in an Argo Rollout"""
    logger.info(f"Updating rollout {rollout_name} with steps {steps}")
    
    try:
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
        
        logger.info(f"Successfully updated rollout {rollout_name}")
        
        # Store the update in our database
        deployment_data = {
            'service_name': rollout_name,
            'version': rollout['spec']['template']['spec']['containers'][0]['image'],
            'canary_increment': steps[0],
            'timestamp': datetime.now(),
            'metrics_json': get_current_metrics()
        }
        data_manager.store_deployment_data(deployment_data)
        
    except Exception as e:
        logger.error(f"Error updating rollout: {e}")

def collect_deployment_data():
    """Collect deployment data from various sources for model training"""
    logger.info("Collecting historical deployment data")
    
    try:
        # Get data from our database
        return data_manager.get_training_data()
    except Exception as e:
        logger.error(f"Error collecting deployment data: {e}")
        return pd.DataFrame()  # Return empty DataFrame on error

def main_loop():
    """Main controller loop"""
    logger.info("Starting auto-tuning controller")
    
    while True:
        try:
            # Train model with historical data
            deployment_data = collect_deployment_data()
            if not deployment_data.empty:
                logger.info(f"Training model with {len(deployment_data)} data points")
                tuner.train(deployment_data)
            
            # Get current metrics
            metrics = get_current_metrics()
            
            # Get recommended canary steps
            steps = tuner.recommend_canary_steps(metrics)
            logger.info(f"Recommended canary steps: {steps}")
            
            # Update the frontend rollout
            update_rollout_steps("frontend", "default", steps)
            
        except Exception as e:
            logger.error(f"Error in auto-tuning controller main loop: {e}")
            
        # Run every 6 hours
        logger.info("Sleeping for 6 hours before next optimization cycle")
        time.sleep(6 * 60 * 60)

if __name__ == "__main__":
    main_loop()