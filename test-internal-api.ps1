# Test Internal API Connectivity from Power Platform
# This script verifies that Power Platform can access the internal API through VNet integration

param(
    [Parameter(Mandatory=$false)]
    [string]$EnvironmentId = "50f3edf1-abe7-e31d-9602-dc56f4f3e404",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "PPVNetUS-rs",
    
    [Parameter(Mandatory=$true)]
    [string]$WebAppName
)

Write-Host "=== Testing Internal API Connectivity ===" -ForegroundColor Cyan
Write-Host "This verifies Power Platform can access the private API through VNet" -ForegroundColor Yellow

# Import required modules
Write-Host "`n[1/4] Checking PowerShell modules..." -ForegroundColor Green
try {
    Import-Module Microsoft.PowerPlatform.EnterprisePolicies -ErrorAction Stop
    Import-Module Az.Network -ErrorAction Stop
    Import-Module Az.Websites -ErrorAction Stop
    Write-Host "  ✓ All required modules loaded" -ForegroundColor Gray
} catch {
    Write-Host "  ✗ Error loading modules: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Please run: Install-Module Microsoft.PowerPlatform.EnterprisePolicies -Force" -ForegroundColor Yellow
    exit 1
}

# Get Web App details
Write-Host "`n[2/4] Getting Web App configuration..." -ForegroundColor Green
try {
    $webApp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName -ErrorAction Stop
    
    # Get private endpoint
    $privateEndpointName = "$WebAppName-private-endpoint"
    $privateEndpoint = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -Name $privateEndpointName -ErrorAction Stop
    
    # Get private IP
    $networkInterface = Get-AzNetworkInterface -ResourceId ($privateEndpoint.NetworkInterfaces[0].Id)
    $privateIpAddress = $networkInterface.IpConfigurations[0].PrivateIpAddress
    
    Write-Host "  ✓ Web App: $WebAppName" -ForegroundColor Gray
    Write-Host "  ✓ Private IP: $privateIpAddress" -ForegroundColor Gray
    Write-Host "  ✓ Public Access: Disabled" -ForegroundColor Gray
} catch {
    Write-Host "  ✗ Error getting Web App details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test DNS Resolution
Write-Host "`n[3/4] Testing DNS Resolution..." -ForegroundColor Green
try {
    $dnsResult = Test-DnsResolution -EnvironmentId $EnvironmentId -HostName "$WebAppName.azurewebsites.net"
    
    if ($dnsResult) {
        Write-Host "  ✓ DNS Resolution: SUCCESS" -ForegroundColor Green
        Write-Host "    Hostname: $WebAppName.azurewebsites.net" -ForegroundColor Gray
        
        # Check if it resolves to private IP
        if ($dnsResult.IPAddresses -contains $privateIpAddress) {
            Write-Host "    Resolved to: $privateIpAddress (Private IP) ✓" -ForegroundColor Green
        } else {
            Write-Host "    Resolved to: $($dnsResult.IPAddresses -join ', ')" -ForegroundColor Yellow
            Write-Host "    Expected: $privateIpAddress" -ForegroundColor Yellow
            Write-Host "    ⚠ DNS may still be propagating. Wait 5-10 minutes." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⚠ DNS Resolution: No result" -ForegroundColor Yellow
        Write-Host "    Private endpoint DNS may still be propagating" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ✗ DNS Resolution failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    This may be normal if the private endpoint was just created" -ForegroundColor Yellow
}

# Test Network Connectivity
Write-Host "`n[4/4] Testing Network Connectivity..." -ForegroundColor Green
try {
    $connectivityResult = Test-NetworkConnectivity `
        -EnvironmentId $EnvironmentId `
        -RemoteHost $privateIpAddress `
        -RemotePort 443
    
    if ($connectivityResult.Connected) {
        Write-Host "  ✓ Network Connectivity: SUCCESS" -ForegroundColor Green
        Write-Host "    Target: $privateIpAddress:443" -ForegroundColor Gray
        Write-Host "    Status: Connected" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Network Connectivity: FAILED" -ForegroundColor Red
        Write-Host "    Target: $privateIpAddress:443" -ForegroundColor Gray
        Write-Host "    Error: $($connectivityResult.Error)" -ForegroundColor Red
    }
} catch {
    Write-Host "  ✗ Connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Summary and Next Steps
Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Configuration:" -ForegroundColor White
Write-Host "  • Environment ID: $EnvironmentId" -ForegroundColor Gray
Write-Host "  • Web App: $WebAppName" -ForegroundColor Gray
Write-Host "  • Private IP: $privateIpAddress" -ForegroundColor Gray
Write-Host ""
Write-Host "🔌 Custom Connector Configuration:" -ForegroundColor White
Write-Host "  • Base URL: https://$WebAppName.azurewebsites.net" -ForegroundColor Cyan
Write-Host "  • Available Endpoints:" -ForegroundColor Gray
Write-Host "    - GET /api/health    (Health check)" -ForegroundColor Gray
Write-Host "    - GET /api/data      (Sample data)" -ForegroundColor Gray
Write-Host "    - POST /api/echo     (Echo service)" -ForegroundColor Gray
Write-Host ""
Write-Host "📖 Next Steps for Custom Connector:" -ForegroundColor White
Write-Host "  1. In Power Apps/Power Automate, create a new Custom Connector" -ForegroundColor Gray
Write-Host "  2. Set Host: $WebAppName.azurewebsites.net" -ForegroundColor Gray
Write-Host "  3. Configure actions for the endpoints above" -ForegroundColor Gray
Write-Host "  4. Test the connector from your VNet-integrated environment" -ForegroundColor Gray
Write-Host ""
Write-Host "⚠ Troubleshooting:" -ForegroundColor Yellow
Write-Host "  • If DNS/connectivity fails, wait 10-15 minutes for propagation" -ForegroundColor Gray
Write-Host "  • Run: .\troubleshoot-vnet-integration.ps1 for detailed diagnostics" -ForegroundColor Gray
Write-Host "  • Verify environment is in the same region as the VNet" -ForegroundColor Gray
Write-Host ""
