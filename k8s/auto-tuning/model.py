import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
import joblib
import os

class DeploymentTuner:
    def __init__(self, model_path='model.pkl'):
        self.model_path = model_path
        if os.path.exists(model_path):
            self.model = joblib.load(model_path)
        else:
            self.model = RandomForestRegressor(n_estimators=100, random_state=42)
            
    def train(self, deployment_data):
        """
        Train the model on historical deployment data
        
        deployment_data: DataFrame with columns:
        - traffic_level: Average requests per second during deployment
        - error_rate_prev: Error rate from previous deployment
        - deploy_time: Time of day (0-23)
        - deploy_day: Day of week (0-6)
        - canary_increment: Size of canary increments (%)
        - success_rate: Target variable (0-1 success rate of deployment)
        """
        X = deployment_data[['traffic_level', 'error_rate_prev', 
                          'deploy_time', 'deploy_day']]
        y = deployment_data['canary_increment']
        
        self.model.fit(X, y)
        joblib.dump(self.model, self.model_path)
        
    def recommend_canary_steps(self, current_metrics):
        """
        Recommend optimal canary deployment steps based on current metrics
        
        Returns a list of canary steps (percentages)
        """
        X = pd.DataFrame([current_metrics])
        
        # Predict optimal canary increment
        optimal_increment = max(5, min(40, int(self.model.predict(X)[0])))
        
        # Generate canary steps based on optimal increment
        steps = []
        current = optimal_increment
        while current < 100:
            steps.append(current)
            current += optimal_increment
        
        if steps[-1] < 100:
            steps.append(100)
            
        return steps