param (
    [string]$Namespace = "default",
    [string]$EnvFile = ".env.local"
)

# Check if env file exists
if (-not (Test-Path $EnvFile)) {
    Write-Host "Environment file $EnvFile not found!" -ForegroundColor Red
    exit 1
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
    $key = $Matches[1].Trim()
    $value = $Matches[2]
    
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
