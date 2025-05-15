param (
    [string]$Namespace = "default",
    [string]$EnvFile = ".env.local"
)

# Check if env file exists
if (-not (Test-Path $EnvFile)) {
    Write-Host "Environment file $EnvFile not found. Creating template..." -ForegroundColor Yellow
    @"
# SMU Application Environment Variables
# Replace these with your actual values

# API Keys
API_KEY=your_api_key_here

# Database
DB_HOST=localhost
DB_USER=smu_user
DB_PASSWORD=changeme
DB_NAME=smu_db

# App Settings
NODE_ENV=development
"@ | Out-File -FilePath $EnvFile
    
    Write-Host "Created template $EnvFile. Please edit with your actual values and run this script again." -ForegroundColor Yellow
    exit 0
}

# Read env file and create Kubernetes secret
Write-Host "Creating Kubernetes secret from $EnvFile..." -ForegroundColor Green

# Create a temporary file for the secret
$tempFile = [System.IO.Path]::GetTempFileName()

@"
apiVersion: v1
kind: Secret
metadata:
  name: smu-config
  namespace: $Namespace
type: Opaque
data:
"@ | Out-File -FilePath $tempFile

# Process each line in the env file
Get-Content $EnvFile | Where-Object { $_ -match "^\s*([^#][^=]+)=(.*)$" } | ForEach-Object {
    $key = $matches[1].Trim()
    $value = $matches[2]
    
    # Convert value to base64 for Kubernetes secret
    $base64Value = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($value))
    
    # Add to secret file
    "  $key`: $base64Value" | Out-File -FilePath $tempFile -Append
}

# Apply secret to cluster
kubectl apply -f $tempFile

# Clean up temp file
Remove-Item $tempFile

Write-Host "Secret 'smu-config' applied to namespace '$Namespace'" -ForegroundColor Green