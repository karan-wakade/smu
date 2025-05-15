param (
    [string]$Namespace = "monitoring"
)

# Create monitoring namespace
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repos
Write-Host "Adding Helm repositories..." -ForegroundColor Green
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus
Write-Host "Installing Prometheus..." -ForegroundColor Green
helm upgrade --install prometheus prometheus-community/prometheus `
    --namespace $Namespace `
    --set server.persistentVolume.enabled=false `
    --set alertmanager.persistentVolume.enabled=false

# Install Grafana
Write-Host "Installing Grafana..." -ForegroundColor Green
helm upgrade --install grafana grafana/grafana `
    --namespace $Namespace `
    --set persistence.enabled=false `
    --set service.type=ClusterIP `
    --set admin.password=admin123 `
    --set dashboardProviders."dashboardproviders\.yaml".apiVersion=1 `
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].name=default `
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].orgId=1 `
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].folder="" `
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].type=file `
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].disableDeletion=false `
    --set dashboardProviders."dashboardproviders\.yaml".providers[0].options.path="/var/lib/grafana/dashboards/default"

# Create basic dashboard ConfigMap
$dashboardJson = @'
{
  "annotations": {
    "list": []
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": 1,
  "links": [],
  "panels": [
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "never",
            "spanNulls": true
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 9,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "title": "Memory Usage",
      "type": "timeseries",
      "targets": [
        {
          "expr": "sum(container_memory_usage_bytes{pod=~\"staging-rollout.*\",container=\"smu-container\"}) by (pod)",
          "refId": "A",
          "legendFormat": "{{pod}}"
        }
      ]
    },
    {
      "datasource": "Prometheus",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "never",
            "spanNulls": true
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 9,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "id": 3,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "title": "CPU Usage",
      "type": "timeseries",
      "targets": [
        {
          "expr": "sum(rate(container_cpu_usage_seconds_total{pod=~\"staging-rollout.*\",container=\"smu-container\"}[5m])) by (pod)",
          "refId": "A",
          "legendFormat": "{{pod}}"
        }
      ]
    }
  ],
  "refresh": "10s",
  "schemaVersion": 30,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "SMU Application Dashboard",
  "uid": "smu-dashboard",
  "version": 1
}
'@

$dashboardConfigMap = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: smu-dashboard
  namespace: $Namespace
  labels:
    grafana_dashboard: "1"
data:
  smu-dashboard.json: |
$($dashboardJson -replace '(?m)^', '    ')
"@

$dashboardConfigMap | Out-File -FilePath "smu-dashboard.yaml" -Encoding utf8
kubectl apply -f "smu-dashboard.yaml"
Remove-Item "smu-dashboard.yaml"

# Setup data source
$datasourceConfigMap = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: $Namespace
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.$Namespace.svc.cluster.local
      access: proxy
      isDefault: true
"@

$datasourceConfigMap | Out-File -FilePath "grafana-datasource.yaml" -Encoding utf8
kubectl apply -f "grafana-datasource.yaml"
Remove-Item "grafana-datasource.yaml"

# Setup port-forwarding for Grafana
Write-Host "Setting up port forwarding for Grafana..." -ForegroundColor Green
$grafanaPodName = kubectl get pods -n $Namespace -l "app.kubernetes.io/name=grafana" -o jsonpath="{.items[0].metadata.name}"

Write-Host "Grafana will be available at http://localhost:3000" -ForegroundColor Green
Write-Host "Username: admin" -ForegroundColor Green
Write-Host "Password: admin123" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop port forwarding" -ForegroundColor Yellow

kubectl port-forward -n $Namespace $grafanaPodName 3000:3000