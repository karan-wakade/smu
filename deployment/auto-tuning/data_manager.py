import psycopg2
import pandas as pd
import os
from datetime import datetime
import json

class DeploymentDataManager:
    def __init__(self):
        # Database connection details from environment variables
        self.db_host = os.environ.get('DB_HOST', 'auto-tuner-db')
        self.db_name = os.environ.get('DB_NAME', 'deployment_history')
        self.db_user = os.environ.get('DB_USER', 'postgres')
        self.db_pass = os.environ.get('DB_PASSWORD', 'postgres')
        
        # Initialize database if needed
        self._init_db()
    
    def _init_db(self):
        """Initialize the database with required tables"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        # Create deployments table
        cursor.execute('''
        CREATE TABLE IF NOT EXISTS deployments (
            id SERIAL PRIMARY KEY,
            timestamp TIMESTAMP,
            service_name VARCHAR(100),
            version VARCHAR(100),
            traffic_level FLOAT,
            error_rate_prev FLOAT,
            deploy_time INTEGER,
            deploy_day INTEGER,
            canary_increment INTEGER,
            success_rate FLOAT,
            rollout_duration INTEGER,
            metrics_json TEXT
        )
        ''')
        
        conn.commit()
        conn.close()
    
    def _get_connection(self):
        """Get a connection to the PostgreSQL database"""
        return psycopg2.connect(
            host=self.db_host,
            database=self.db_name,
            user=self.db_user,
            password=self.db_pass
        )
    
    def store_deployment_data(self, deployment_data):
        """Store a new deployment record"""
        conn = self._get_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
        INSERT INTO deployments (
            timestamp, service_name, version, traffic_level, 
            error_rate_prev, deploy_time, deploy_day, 
            canary_increment, success_rate, rollout_duration, metrics_json
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ''', (
            deployment_data.get('timestamp', datetime.now()),
            deployment_data.get('service_name'),
            deployment_data.get('version'),
            deployment_data.get('traffic_level'),
            deployment_data.get('error_rate_prev'),
            deployment_data.get('deploy_time'),
            deployment_data.get('deploy_day'),
            deployment_data.get('canary_increment'),
            deployment_data.get('success_rate'),
            deployment_data.get('rollout_duration'),
            json.dumps(deployment_data.get('metrics_json', {}))
        ))
        
        conn.commit()
        conn.close()
    
    def get_training_data(self, limit=100):
        """Retrieve historical deployment data for model training"""
        conn = self._get_connection()
        
        query = '''
        SELECT 
            traffic_level, error_rate_prev, deploy_time, deploy_day,
            canary_increment, success_rate, rollout_duration
        FROM deployments
        ORDER BY timestamp DESC
        LIMIT %s
        '''
        
        df = pd.read_sql(query, conn, params=(limit,))
        conn.close()
        
        return df