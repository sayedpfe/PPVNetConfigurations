# Troubleshooting script for Power Platform VNet Integration
# This script helps diagnose and verify VNet integration configuration

# Variables - Update these to match your environment
$powerPlatformEnvironmentId = "50f3edf1-abe7-e31d-9602-dc56f4f3e404"
$resourceGroupName = "PPVNetUS-rs"
$keyVaultName = "kv-power-app-2025"
$vNetNameAE = "vnet-power-platform-test-eus"
$vNetNameASE = "vnet-power-platform-test-wus"
$vNetRegionAE = "eastus"
$vNetRegionASE = "westus"
$enterprisePolicyName = "Power-Platform-Test-Vnet-Injection-Enterprise-Policy"
$subscriptionId = (Get-AzContext).Subscription.Id

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Power Platform VNet Integration Diagnostics" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

#########
# 1. Verify Azure Authentication
Write-Host "[1/6] Checking Azure Authentication..." -ForegroundColor Yellow
try {
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context) {
        Write-Host "✗ Not authenticated to Azure" -ForegroundColor Red
        Write-Host "Please run: Connect-AzAccount" -ForegroundColor Yellow
        exit
    }
    Write-Host "✓ Authenticated as: $($context.Account)" -ForegroundColor Green
    Write-Host "✓ Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
} catch {
    Write-Host "✗ Error checking Azure authentication: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

#########
# 2. Verify Azure Resources Exist
Write-Host "`n[2/6] Verifying Azure Resources..." -ForegroundColor Yellow

# Check Resource Group
try {
    $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction Stop
    Write-Host "✓ Resource Group: $resourceGroupName exists" -ForegroundColor Green
} catch {
    Write-Host "✗ Resource Group: $resourceGroupName not found" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Check Key Vault
try {
    $kv = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -ErrorAction Stop
    Write-Host "✓ Key Vault: $keyVaultName exists" -ForegroundColor Green
    Write-Host "  - Public Network Access: $($kv.PublicNetworkAccess)" -ForegroundColor Gray
    Write-Host "  - Network ACLs Default Action: $($kv.NetworkAcls.DefaultAction)" -ForegroundColor Gray
    Write-Host "  - Network Rules Count: $($kv.NetworkAcls.VirtualNetworkRules.Count)" -ForegroundColor Gray
} catch {
    Write-Host "✗ Key Vault: $keyVaultName not found" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Check Virtual Networks
try {
    $vnetAE = Get-AzVirtualNetwork -Name $vNetNameAE -ResourceGroupName $resourceGroupName -ErrorAction Stop
    Write-Host "✓ VNet: $vNetNameAE exists in $($vnetAE.Location)" -ForegroundColor Green
    Write-Host "  - Subnets: $($vnetAE.Subnets.Count)" -ForegroundColor Gray
    foreach ($subnet in $vnetAE.Subnets) {
        $delegationInfo = if ($subnet.Delegations.Count -gt 0) { " [Delegated to: $($subnet.Delegations[0].ServiceName)]" } else { "" }
        Write-Host "    • $($subnet.Name) ($($subnet.AddressPrefix))$delegationInfo" -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ VNet: $vNetNameAE not found" -ForegroundColor Red
}

try {
    $vnetASE = Get-AzVirtualNetwork -Name $vNetNameASE -ResourceGroupName $resourceGroupName -ErrorAction Stop
    Write-Host "✓ VNet: $vNetNameASE exists in $($vnetASE.Location)" -ForegroundColor Green
    Write-Host "  - Subnets: $($vnetASE.Subnets.Count)" -ForegroundColor Gray
    foreach ($subnet in $vnetASE.Subnets) {
        $delegationInfo = if ($subnet.Delegations.Count -gt 0) { " [Delegated to: $($subnet.Delegations[0].ServiceName)]" } else { "" }
        Write-Host "    • $($subnet.Name) ($($subnet.AddressPrefix))$delegationInfo" -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ VNet: $vNetNameASE not found" -ForegroundColor Red
}

# Check Enterprise Policy
try {
    $enterprisePolicyResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.PowerPlatform/enterprisePolicies/$enterprisePolicyName"
    $policy = Get-AzResource -ResourceId $enterprisePolicyResourceId -ErrorAction Stop
    Write-Host "✓ Enterprise Policy: $enterprisePolicyName exists" -ForegroundColor Green
    Write-Host "  - Resource ID: $($policy.ResourceId)" -ForegroundColor Gray
    Write-Host "  - Location: $($policy.Location)" -ForegroundColor Gray
} catch {
    Write-Host "✗ Enterprise Policy: $enterprisePolicyName not found" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

#########
# 3. Check Power Platform Module
Write-Host "`n[3/6] Checking Power Platform Module..." -ForegroundColor Yellow
try {
    $module = Get-Module -Name Microsoft.PowerPlatform.EnterprisePolicies -ListAvailable -ErrorAction Stop
    if ($null -eq $module) {
        Write-Host "✗ Microsoft.PowerPlatform.EnterprisePolicies module not installed" -ForegroundColor Red
        Write-Host "  To install: Install-Module -Name Microsoft.PowerPlatform.EnterprisePolicies -Scope CurrentUser" -ForegroundColor Yellow
    } else {
        Write-Host "✓ Microsoft.PowerPlatform.EnterprisePolicies module installed (Version: $($module.Version))" -ForegroundColor Green
        Import-Module Microsoft.PowerPlatform.EnterprisePolicies -ErrorAction Stop
        Write-Host "✓ Module loaded successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "✗ Error with Power Platform module: $($_.Exception.Message)" -ForegroundColor Red
}

#########
# 4. Test Power Platform Environment VNet Integration
Write-Host "`n[4/6] Testing Power Platform VNet Integration..." -ForegroundColor Yellow
Write-Host "Note: This may take a few seconds..." -ForegroundColor Gray

try {
    Import-Module Microsoft.PowerPlatform.EnterprisePolicies -ErrorAction Stop
    
    # Test Get-EnvironmentRegion
    try {
        Write-Host "`nTesting Get-EnvironmentRegion..." -ForegroundColor Cyan
        $envRegion = Get-EnvironmentRegion -EnvironmentId $powerPlatformEnvironmentId -ErrorAction Stop
        Write-Host "✓ Environment Region Retrieved Successfully!" -ForegroundColor Green
        Write-Host "  Region: $envRegion" -ForegroundColor Gray
        Write-Host "`n✓✓✓ VNet Integration is ACTIVE and WORKING! ✓✓✓" -ForegroundColor Green -BackgroundColor Black
        
        # Verify regions match
        Write-Host "`nVerifying region compatibility..." -ForegroundColor Cyan
        Write-Host "  - Expected VNet Regions: $vNetRegionAE, $vNetRegionASE" -ForegroundColor Gray
        Write-Host "  - Environment Region: $envRegion" -ForegroundColor Gray
        
    } catch {
        Write-Host "✗ Failed to retrieve environment region" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Message -like "*Subnet information not found*") {
            Write-Host "`n⚠ DIAGNOSIS: VNet Integration Not Applied Yet" -ForegroundColor Yellow
            Write-Host "`nPossible Reasons:" -ForegroundColor Yellow
            Write-Host "  1. VNet injection is still being processed (can take 5-15 minutes)" -ForegroundColor White
            Write-Host "  2. Enterprise policy was not successfully linked to the environment" -ForegroundColor White
            Write-Host "  3. The environment is not a Managed Environment" -ForegroundColor White
            Write-Host "  4. The environment ID is incorrect" -ForegroundColor White
            
            Write-Host "`nNext Steps:" -ForegroundColor Yellow
            Write-Host "  1. Verify in Power Platform Admin Center:" -ForegroundColor White
            Write-Host "     https://admin.powerplatform.microsoft.com" -ForegroundColor Cyan
            Write-Host "  2. Navigate to: Environments > [Your Environment] > History" -ForegroundColor White
            Write-Host "  3. Look for VNet injection operation and verify status is 'Succeeded'" -ForegroundColor White
            Write-Host "  4. If operation is still 'In Progress', wait and try again" -ForegroundColor White
            Write-Host "  5. If operation 'Failed', check the error message" -ForegroundColor White
        }
        
        if ($_.Exception.Message -like "*NotFound*" -or $_.Exception.Message -like "*404*") {
            Write-Host "`n⚠ The environment might not exist or you don't have access" -ForegroundColor Yellow
            Write-Host "  Environment ID: $powerPlatformEnvironmentId" -ForegroundColor Gray
        }
    }
    
    # Test Get-EnvironmentUsage (if previous test succeeded)
    if ($envRegion) {
        try {
            Write-Host "`nTesting Get-EnvironmentUsage..." -ForegroundColor Cyan
            $envUsage = Get-EnvironmentUsage -EnvironmentId $powerPlatformEnvironmentId -ErrorAction Stop
            Write-Host "✓ Environment Usage Retrieved Successfully!" -ForegroundColor Green
            Write-Host "  Usage Info: $envUsage" -ForegroundColor Gray
        } catch {
            Write-Host "⚠ Get-EnvironmentUsage failed (this is optional): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "✗ Power Platform module not available or error occurred" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

#########
# 5. Test DNS Resolution (if module is available)
Write-Host "`n[5/6] Testing DNS Resolution..." -ForegroundColor Yellow
try {
    Import-Module Microsoft.PowerPlatform.EnterprisePolicies -ErrorAction Stop
    
    $testHostname = "$keyVaultName.vault.azure.net"
    Write-Host "Testing DNS resolution for: $testHostname" -ForegroundColor Cyan
    
    try {
        $dnsResult = Test-DnsResolution -EnvironmentId $powerPlatformEnvironmentId -HostName $testHostname -ErrorAction Stop
        Write-Host "✓ DNS Resolution Test Completed!" -ForegroundColor Green
        Write-Host "  Result: $dnsResult" -ForegroundColor Gray
    } catch {
        Write-Host "✗ DNS Resolution Test Failed" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Message -like "*Subnet information not found*") {
            Write-Host "  ⚠ VNet integration must be active before DNS testing can work" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "⚠ Skipping DNS tests - module not available" -ForegroundColor Yellow
}

#########
# 6. Summary and Recommendations
Write-Host "`n[6/6] Summary and Recommendations" -ForegroundColor Yellow
Write-Host "=========================================`n" -ForegroundColor Cyan

Write-Host "Configuration Details:" -ForegroundColor White
Write-Host "  • Resource Group: $resourceGroupName" -ForegroundColor Gray
Write-Host "  • Key Vault: $keyVaultName" -ForegroundColor Gray
Write-Host "  • Environment ID: $powerPlatformEnvironmentId" -ForegroundColor Gray
Write-Host "  • Enterprise Policy: $enterprisePolicyName" -ForegroundColor Gray
Write-Host "  • VNets: $vNetNameAE, $vNetNameASE" -ForegroundColor Gray

# Try to get Key Vault private IP for connectivity test
try {
    $privateEndpoint = Get-AzPrivateEndpoint -Name "$keyVaultName-private-endpoint" -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
    if ($privateEndpoint) {
        $networkInterface = Get-AzNetworkInterface -ResourceId ($privateEndpoint.NetworkInterfaces[0].Id) -ErrorAction SilentlyContinue
        $privateIpAddress = $networkInterface.IpConfigurations[0].PrivateIpAddress
        Write-Host "  • Key Vault Private IP: $privateIpAddress" -ForegroundColor Gray
    }
} catch {
    # Silently continue if unable to get private IP
}

Write-Host "`nUseful Commands:" -ForegroundColor White
Write-Host "  # Check environment region" -ForegroundColor Gray
Write-Host "  Get-EnvironmentRegion -EnvironmentId '$powerPlatformEnvironmentId'" -ForegroundColor Cyan
Write-Host "`n  # Test DNS resolution" -ForegroundColor Gray
Write-Host "  Test-DnsResolution -EnvironmentId '$powerPlatformEnvironmentId' -HostName '$keyVaultName.vault.azure.net'" -ForegroundColor Cyan
Write-Host "`n  # Test network connectivity to Key Vault" -ForegroundColor Gray
if ($privateIpAddress) {
    Write-Host "  Test-NetworkConnectivity -EnvironmentId '$powerPlatformEnvironmentId' -RemoteHost '$privateIpAddress' -RemotePort 443" -ForegroundColor Cyan
} else {
    Write-Host "  Test-NetworkConnectivity -EnvironmentId '$powerPlatformEnvironmentId' -RemoteHost '<Key-Vault-Private-IP>' -RemotePort 443" -ForegroundColor Cyan
    Write-Host "  (Replace <Key-Vault-Private-IP> with your Key Vault's private endpoint IP address)" -ForegroundColor Yellow
}

Write-Host "`nAdditional Resources:" -ForegroundColor White
Write-Host "  • Power Platform Admin Center: https://admin.powerplatform.microsoft.com" -ForegroundColor Cyan
Write-Host "  • VNet Support Docs: https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview" -ForegroundColor Cyan
Write-Host "  • Troubleshooting Guide: https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network" -ForegroundColor Cyan
Write-Host "  • GitHub Samples: https://github.com/microsoft/PowerPlatform-EnterprisePolicies" -ForegroundColor Cyan

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Diagnostics Complete!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
