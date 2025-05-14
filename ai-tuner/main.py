import os
import time
import logging
import numpy as np
import pandas as pd
from flask import Flask, jsonify, request
import prometheus_client
from prometheus_api_client import PrometheusConnect

app = Flask(__name__)
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
logger = logging.getLogger(__name__)

# Connect to Prometheus
prom = PrometheusConnect(url=os.environ.get("PROMETHEUS_URL", "http://prometheus-server.monitoring:9090"))

# Load config
import yaml
with open("/etc/ai-tuner/config.yaml", "r") as f:
    config = yaml.safe_load(f)

# Recommendation history
history = []

@app.route("/health")
def health():
    return jsonify({"status": "healthy"})

@app.route("/metrics")
def metrics():
    return prometheus_client.generate_latest()

@app.route("/analyze", methods=["GET", "POST"])
def analyze():
    try:
        # Collect metrics from Prometheus
        metrics_data = {}
        metrics_weight = {}
        total_score = 0
        total_weight = 0
        
        for metric in config["analysis"]["metrics"]:
            query_result = prom.custom_query(metric["query"])
            
            if query_result and len(query_result) > 0:
                value = float(query_result[0]["value"][1])
                threshold = metric["threshold"]
                weight = metric["weight"]
                
                # Calculate normalized score (0-1)
                if metric["name"] in ["success-rate"]:
                    # Higher is better
                    score = min(value / threshold, 1.0)
                else:
                    # Lower is better
                    score = max(0, min(1.0, threshold / (value if value > 0 else threshold)))
                
                metrics_data[metric["name"]] = {
                    "value": value,
                    "threshold": threshold,
                    "score": score
                }
                
                total_score += score * weight
                total_weight += weight
            else:
                logger.warning(f"No data for metric {metric['name']}")
        
        # Calculate weighted score
        final_score = total_score / total_weight if total_weight > 0 else 0
        
        # Get recommendation based on score
        if final_score < config["recommendation"]["rollback_threshold"]:
            recommendation = "rollback"
        elif final_score > config["recommendation"]["promotion_threshold"]:
            recommendation = "promote"
        else:
            recommendation = "continue"
        
        # Store in history
        timestamp = time.time()
        history.append({
            "timestamp": timestamp,
            "metrics": metrics_data,
            "score": final_score,
            "recommendation": recommendation
        })
        
        # Keep history window limited
        if len(history) > config["tuning"]["history_window"]:
            history.pop(0)
        
        # Return analysis result
        return jsonify({
            "timestamp": timestamp,
            "metrics": metrics_data,
            "score": final_score,
            "recommendation": recommendation
        })
    
    except Exception as e:
        logger.error(f"Error in analysis: {str(e)}")
        return jsonify({
            "error": str(e),
            "recommendation": "continue"  # Default to continue on error
        })

@app.route("/dashboard")
def dashboard():
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>AI Tuner Dashboard</title>
        <meta http-equiv="refresh" content="10">
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .metric { margin-bottom: 10px; padding: 10px; border: 1px solid #ddd; }
            .good { background-color: #d4edda; }
            .warn { background-color: #fff3cd; }
            .bad { background-color: #f8d7da; }
            .score { font-size: 24px; font-weight: bold; margin: 20px 0; }
        </style>
    </head>
    <body>
        <h1>AI Tuner Dashboard</h1>
        <div id="data">Loading...</div>
        
        <script>
            fetch('/analyze')
                .then(response => response.json())
                .then(data => {
                    let html = `<div class="score">Overall Score: ${(data.score * 100).toFixed(2)}%</div>`;
                    html += `<div>Recommendation: <strong>${data.recommendation.toUpperCase()}</strong></div>`;
                    html += '<h2>Metrics</h2>';
                    
                    for (const [key, metric] of Object.entries(data.metrics)) {
                        let cls = metric.score > 0.8 ? 'good' : (metric.score < 0.5 ? 'bad' : 'warn');
                        html += `<div class="metric ${cls}">
                            <strong>${key}</strong>: ${metric.value.toFixed(2)}
                            (threshold: ${metric.threshold})
                            <div>Score: ${(metric.score * 100).toFixed(2)}%</div>
                        </div>`;
                    }
                    
                    document.getElementById('data').innerHTML = html;
                });
        </script>
    </body>
    </html>
    """

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)