# Deploy Internal API for Custom Connector Simulation
# This script deploys an Azure App Service with a private endpoint to simulate an internal API
# that can only be accessed through VNet integration (for Power Platform custom connectors)

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "476f3985-4e26-4f7d-8fcf-9f25f4da27a7",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "PPVNetUS-rs",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$AppServicePlanName = "asp-internal-api",
    
    [Parameter(Mandatory=$false)]
    [string]$WebAppName = "internal-api-demo-$((Get-Random -Minimum 1000 -Maximum 9999))",
    
    [Parameter(Mandatory=$false)]
    [string]$VNetName = "PPVNet-eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$PrivateEndpointSubnetName = "subnet-private-endpoints-eus",
    
    [Parameter(Mandatory=$false)]
    [string]$PrivateDnsZoneName = "privatelink.azurewebsites.net"
)

Write-Host "=== Deploying Internal API for Custom Connector Simulation ===" -ForegroundColor Cyan
Write-Host "This will create a private Web API accessible only through VNet" -ForegroundColor Yellow

# Set subscription context
Write-Host "`n[1/8] Setting Azure subscription context..." -ForegroundColor Green
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# Create App Service Plan (Basic B1 tier - cost-effective)
Write-Host "`n[2/8] Creating App Service Plan..." -ForegroundColor Green
$appServicePlan = Get-AzAppServicePlan -ResourceGroupName $ResourceGroupName -Name $AppServicePlanName -ErrorAction SilentlyContinue
if (-not $appServicePlan) {
    $appServicePlan = New-AzAppServicePlan `
        -ResourceGroupName $ResourceGroupName `
        -Name $AppServicePlanName `
        -Location $Location `
        -Tier "Basic" `
        -NumberofWorkers 1 `
        -WorkerSize "Small"
    Write-Host "  ✓ App Service Plan created: $AppServicePlanName" -ForegroundColor Gray
} else {
    Write-Host "  ℹ App Service Plan already exists: $AppServicePlanName" -ForegroundColor Yellow
}

# Create Web App
Write-Host "`n[3/8] Creating Web App..." -ForegroundColor Green
$webApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName -ErrorAction SilentlyContinue
if (-not $webApp) {
    $webApp = New-AzWebApp `
        -ResourceGroupName $ResourceGroupName `
        -Name $WebAppName `
        -Location $Location `
        -AppServicePlan $AppServicePlanName
    Write-Host "  ✓ Web App created: $WebAppName" -ForegroundColor Gray
} else {
    Write-Host "  ℹ Web App already exists: $WebAppName" -ForegroundColor Yellow
}

# Configure Web App with a simple API response
Write-Host "`n[4/8] Configuring Web App settings..." -ForegroundColor Green

# Add app settings to create a simple API endpoint
$appSettings = @{
    "WEBSITE_RUN_FROM_PACKAGE" = "0"
    "API_MESSAGE" = "This is an internal API accessible only through VNet"
}

Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName -AppSettings $appSettings | Out-Null
Write-Host "  ✓ App settings configured" -ForegroundColor Gray

# Disable public network access
Write-Host "`n[5/8] Disabling public network access..." -ForegroundColor Green
$webApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
$webApp.SiteConfig.PublicNetworkAccess = "Disabled"
Set-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName -SiteConfig $webApp.SiteConfig | Out-Null
Write-Host "  ✓ Public access disabled" -ForegroundColor Gray

# Get VNet and subnet information
Write-Host "`n[6/8] Getting VNet configuration..." -ForegroundColor Green
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $PrivateEndpointSubnetName
Write-Host "  ✓ VNet: $VNetName" -ForegroundColor Gray
Write-Host "  ✓ Subnet: $PrivateEndpointSubnetName" -ForegroundColor Gray

# Create Private Endpoint
Write-Host "`n[7/8] Creating Private Endpoint..." -ForegroundColor Green
$privateEndpointName = "$WebAppName-private-endpoint"
$privateEndpoint = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -Name $privateEndpointName -ErrorAction SilentlyContinue

if (-not $privateEndpoint) {
    # Create private link service connection
    $privateLinkConnection = New-AzPrivateLinkServiceConnection `
        -Name "$privateEndpointName-connection" `
        -PrivateLinkServiceId $webApp.Id `
        -GroupId "sites"
    
    # Create private endpoint
    $privateEndpoint = New-AzPrivateEndpoint `
        -ResourceGroupName $ResourceGroupName `
        -Name $privateEndpointName `
        -Location $Location `
        -Subnet $subnet `
        -PrivateLinkServiceConnection $privateLinkConnection
    
    Write-Host "  ✓ Private Endpoint created: $privateEndpointName" -ForegroundColor Gray
} else {
    Write-Host "  ℹ Private Endpoint already exists: $privateEndpointName" -ForegroundColor Yellow
}

# Get Private IP Address
$networkInterface = Get-AzNetworkInterface -ResourceId ($privateEndpoint.NetworkInterfaces[0].Id)
$privateIpAddress = $networkInterface.IpConfigurations[0].PrivateIpAddress
Write-Host "  ✓ Private IP Address: $privateIpAddress" -ForegroundColor Cyan

# Create or update Private DNS Zone
Write-Host "`n[8/8] Configuring Private DNS..." -ForegroundColor Green
$privateDnsZone = Get-AzPrivateDnsZone -ResourceGroupName $ResourceGroupName -Name $PrivateDnsZoneName -ErrorAction SilentlyContinue

if (-not $privateDnsZone) {
    $privateDnsZone = New-AzPrivateDnsZone `
        -ResourceGroupName $ResourceGroupName `
        -Name $PrivateDnsZoneName
    Write-Host "  ✓ Private DNS Zone created: $PrivateDnsZoneName" -ForegroundColor Gray
} else {
    Write-Host "  ℹ Private DNS Zone already exists: $PrivateDnsZoneName" -ForegroundColor Yellow
}

# Link Private DNS Zone to VNet
$dnsLink = Get-AzPrivateDnsVirtualNetworkLink `
    -ResourceGroupName $ResourceGroupName `
    -ZoneName $PrivateDnsZoneName `
    -Name "$VNetName-link" `
    -ErrorAction SilentlyContinue

if (-not $dnsLink) {
    New-AzPrivateDnsVirtualNetworkLink `
        -ResourceGroupName $ResourceGroupName `
        -ZoneName $PrivateDnsZoneName `
        -Name "$VNetName-link" `
        -VirtualNetworkId $vnet.Id `
        -EnableRegistration $false | Out-Null
    Write-Host "  ✓ DNS Zone linked to VNet" -ForegroundColor Gray
}

# Create DNS record for the Web App
$dnsRecordName = $WebAppName
$existingRecord = Get-AzPrivateDnsRecordSet `
    -ResourceGroupName $ResourceGroupName `
    -ZoneName $PrivateDnsZoneName `
    -Name $dnsRecordName `
    -RecordType A `
    -ErrorAction SilentlyContinue

if (-not $existingRecord) {
    New-AzPrivateDnsRecordSet `
        -ResourceGroupName $ResourceGroupName `
        -ZoneName $PrivateDnsZoneName `
        -Name $dnsRecordName `
        -RecordType A `
        -Ttl 3600 `
        -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $privateIpAddress) | Out-Null
    Write-Host "  ✓ DNS A record created" -ForegroundColor Gray
}

# Deploy simple API code using Kudu
Write-Host "`n[9/9] Deploying sample API code..." -ForegroundColor Green

# Create a simple index.html with API endpoints
$htmlContent = @'
<!DOCTYPE html>
<html>
<head>
    <title>Internal API - Power Platform VNet Integration Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f0f0f0; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; }
        .endpoint { background: #f5f5f5; padding: 15px; margin: 10px 0; border-left: 4px solid #0078d4; }
        .status { color: #107c10; font-weight: bold; }
        code { background: #e1e1e1; padding: 2px 6px; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Internal API - VNet Integration Demo</h1>
        <p class="status">✓ Status: Online (Private Access Only)</p>
        <p>This API is accessible only through VNet integration. Public access is disabled.</p>
        
        <h2>Available Endpoints:</h2>
        
        <div class="endpoint">
            <h3>GET /api/health</h3>
            <p>Health check endpoint</p>
            <p><strong>Response:</strong> <code>{"status": "healthy", "timestamp": "..."}</code></p>
        </div>
        
        <div class="endpoint">
            <h3>GET /api/data</h3>
            <p>Sample data endpoint</p>
            <p><strong>Response:</strong> <code>{"message": "Internal API data", "source": "private-network"}</code></p>
        </div>
        
        <div class="endpoint">
            <h3>POST /api/echo</h3>
            <p>Echo endpoint (returns posted data)</p>
            <p><strong>Request Body:</strong> Any JSON</p>
            <p><strong>Response:</strong> <code>{"echo": {...}, "receivedAt": "..."}</code></p>
        </div>
        
        <h2>Testing from Power Platform:</h2>
        <ol>
            <li>Ensure your Power Platform environment has VNet integration configured</li>
            <li>Create a custom connector pointing to this API</li>
            <li>Test connectivity using the diagnostic scripts</li>
        </ol>
        
        <h2>Network Details:</h2>
        <p><strong>Private IP:</strong> (View in Azure Portal)</p>
        <p><strong>Private DNS:</strong> privatelink.azurewebsites.net</p>
        <p><strong>Public Access:</strong> Disabled</p>
    </div>
</body>
</html>
'@

# Create web.config for simple routing
$webConfig = @'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="API Health" stopProcessing="true">
                    <match url="^api/health$" />
                    <action type="Rewrite" url="api-health.html" />
                </rule>
                <rule name="API Data" stopProcessing="true">
                    <match url="^api/data$" />
                    <action type="Rewrite" url="api-data.html" />
                </rule>
            </rules>
        </rewrite>
        <staticContent>
            <mimeMap fileExtension=".json" mimeType="application/json" />
        </staticContent>
    </system.webServer>
</configuration>
'@

$apiHealthContent = @'
{
    "status": "healthy",
    "timestamp": "2025-12-09T00:00:00Z",
    "service": "Internal API Demo",
    "network": "private-vnet",
    "accessType": "VNet Integration Only"
}
'@

$apiDataContent = @'
{
    "message": "This is internal API data accessible only through VNet",
    "source": "private-network",
    "environment": "Power Platform VNet Integration",
    "data": {
        "customers": [
            {"id": 1, "name": "Customer A", "status": "active"},
            {"id": 2, "name": "Customer B", "status": "active"}
        ],
        "timestamp": "2025-12-09T00:00:00Z"
    }
}
'@

# Save files locally first
$tempPath = Join-Path $env:TEMP "internal-api-deploy"
New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

$htmlContent | Out-File -FilePath (Join-Path $tempPath "index.html") -Encoding UTF8
$webConfig | Out-File -FilePath (Join-Path $tempPath "web.config") -Encoding UTF8
$apiHealthContent | Out-File -FilePath (Join-Path $tempPath "api-health.html") -Encoding UTF8
$apiDataContent | Out-File -FilePath (Join-Path $tempPath "api-data.html") -Encoding UTF8

# Create zip package
$zipPath = Join-Path $env:TEMP "internal-api.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $tempPath "*") -DestinationPath $zipPath

# Deploy using Publish-AzWebApp
Write-Host "  ℹ Deploying package to Web App..." -ForegroundColor Yellow
Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName -ArchivePath $zipPath -Force | Out-Null

# Cleanup temp files
Remove-Item $tempPath -Recurse -Force
Remove-Item $zipPath -Force

Write-Host "  ✓ Sample API code deployed" -ForegroundColor Gray

# Summary
Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "✓ Deployment Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Resource Details:" -ForegroundColor White
Write-Host "  • Web App Name: $WebAppName" -ForegroundColor Gray
Write-Host "  • Private IP: $privateIpAddress" -ForegroundColor Gray
Write-Host "  • Private DNS: $WebAppName.$PrivateDnsZoneName" -ForegroundColor Gray
Write-Host "  • Public Access: Disabled (VNet Only)" -ForegroundColor Gray
Write-Host ""
Write-Host "🧪 Test Commands:" -ForegroundColor White
Write-Host "  # Test DNS Resolution" -ForegroundColor Gray
Write-Host "  Test-DnsResolution -EnvironmentId '50f3edf1-abe7-e31d-9602-dc56f4f3e404' -HostName '$WebAppName.azurewebsites.net'" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # Test Network Connectivity" -ForegroundColor Gray
Write-Host "  Test-NetworkConnectivity -EnvironmentId '50f3edf1-abe7-e31d-9602-dc56f4f3e404' -RemoteHost '$privateIpAddress' -RemotePort 443" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔌 Custom Connector URL:" -ForegroundColor White
Write-Host "  https://$WebAppName.azurewebsites.net" -ForegroundColor Cyan
Write-Host ""
Write-Host "📖 Next Steps:" -ForegroundColor White
Write-Host "  1. Wait 5-10 minutes for private endpoint to fully provision" -ForegroundColor Gray
Write-Host "  2. Test connectivity using the commands above" -ForegroundColor Gray
Write-Host "  3. Create a Power Platform custom connector using the URL" -ForegroundColor Gray
Write-Host "  4. Configure the connector to use your VNet-integrated environment" -ForegroundColor Gray
Write-Host ""
