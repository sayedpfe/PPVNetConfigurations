# Detailed Environment Verification Script
# This script helps verify the exact environment configuration

$powerPlatformEnvironmentId = "50f3edf1-abe7-e31d-9602-dc56f4f3e404"
$subscriptionId = (Get-AzContext).Subscription.Id
$resourceGroupName = "PPVNetUS-rs"
$enterprisePolicyName = "Power-Platform-Test-Vnet-Injection-Enterprise-Policy"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Detailed Environment Verification" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import required modules
Import-Module Microsoft.PowerPlatform.EnterprisePolicies -ErrorAction SilentlyContinue

Write-Host "[1] Checking Environment ID Format..." -ForegroundColor Yellow
Write-Host "Current Environment ID: $powerPlatformEnvironmentId" -ForegroundColor White

# Check if ID has hyphens or not
if ($powerPlatformEnvironmentId -match '-') {
    $envIdWithoutHyphens = $powerPlatformEnvironmentId -replace '-', ''
    Write-Host "⚠ ID contains hyphens. Trying without hyphens..." -ForegroundColor Yellow
    Write-Host "Alternative format: $envIdWithoutHyphens" -ForegroundColor Gray
    
    Write-Host "`nTesting with hyphens..." -ForegroundColor Cyan
    try {
        $result1 = Get-EnvironmentRegion -EnvironmentId $powerPlatformEnvironmentId -ErrorAction Stop
        Write-Host "✓ Success with hyphens: $result1" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed with hyphens: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "`nTesting without hyphens..." -ForegroundColor Cyan
    try {
        $result2 = Get-EnvironmentRegion -EnvironmentId $envIdWithoutHyphens -ErrorAction Stop
        Write-Host "✓ Success without hyphens: $result2" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed without hyphens: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    $envIdWithHyphens = $powerPlatformEnvironmentId.Insert(8,'-').Insert(13,'-').Insert(18,'-').Insert(23,'-')
    Write-Host "⚠ ID doesn't contain hyphens. Trying with hyphens..." -ForegroundColor Yellow
    Write-Host "Alternative format: $envIdWithHyphens" -ForegroundColor Gray
    
    Write-Host "`nTesting without hyphens..." -ForegroundColor Cyan
    try {
        $result1 = Get-EnvironmentRegion -EnvironmentId $powerPlatformEnvironmentId -ErrorAction Stop
        Write-Host "✓ Success without hyphens: $result1" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed without hyphens: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "`nTesting with hyphens..." -ForegroundColor Cyan
    try {
        $result2 = Get-EnvironmentRegion -EnvironmentId $envIdWithHyphens -ErrorAction Stop
        Write-Host "✓ Success with hyphens: $result2" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed with hyphens: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n[2] Checking Enterprise Policy Details..." -ForegroundColor Yellow
try {
    $enterprisePolicyResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.PowerPlatform/enterprisePolicies/$enterprisePolicyName"
    $policy = Get-AzResource -ResourceId $enterprisePolicyResourceId -ErrorAction Stop
    
    Write-Host "✓ Enterprise Policy Found" -ForegroundColor Green
    Write-Host "`nPolicy Details:" -ForegroundColor White
    Write-Host "  Name: $($policy.Name)" -ForegroundColor Gray
    Write-Host "  Location: $($policy.Location)" -ForegroundColor Gray
    Write-Host "  Resource ID: $($policy.ResourceId)" -ForegroundColor Gray
    Write-Host "  Type: $($policy.Type)" -ForegroundColor Gray
    
    if ($policy.Properties) {
        Write-Host "`nPolicy Properties:" -ForegroundColor White
        $policy.Properties | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor Gray
    }
    
} catch {
    Write-Host "✗ Error retrieving enterprise policy: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n[3] Checking Subnet Delegations..." -ForegroundColor Yellow
try {
    $vnetAE = Get-AzVirtualNetwork -Name "vnet-power-platform-test-eus" -ResourceGroupName $resourceGroupName -ErrorAction Stop
    $powerPlatformSubnetAE = $vnetAE.Subnets | Where-Object { $_.Name -eq "subnet-power-platform-test-eus" }
    
    if ($powerPlatformSubnetAE.Delegations.Count -gt 0) {
        Write-Host "✓ East US Subnet is delegated" -ForegroundColor Green
        Write-Host "  Service Name: $($powerPlatformSubnetAE.Delegations[0].ServiceName)" -ForegroundColor Gray
        Write-Host "  Actions: $($powerPlatformSubnetAE.Delegations[0].Actions -join ', ')" -ForegroundColor Gray
        
        # Check for service association links
        if ($powerPlatformSubnetAE.ServiceAssociationLinks) {
            Write-Host "`n  Service Association Links:" -ForegroundColor White
            foreach ($link in $powerPlatformSubnetAE.ServiceAssociationLinks) {
                Write-Host "    - Name: $($link.Name)" -ForegroundColor Gray
                Write-Host "      Linked Resource: $($link.LinkedResourceType)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠ No service association links found" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ East US Subnet is NOT delegated" -ForegroundColor Red
    }
    
    $vnetASE = Get-AzVirtualNetwork -Name "vnet-power-platform-test-wus" -ResourceGroupName $resourceGroupName -ErrorAction Stop
    $powerPlatformSubnetASE = $vnetASE.Subnets | Where-Object { $_.Name -eq "subnet-power-platform-test-wus" }
    
    if ($powerPlatformSubnetASE.Delegations.Count -gt 0) {
        Write-Host "`n✓ West US Subnet is delegated" -ForegroundColor Green
        Write-Host "  Service Name: $($powerPlatformSubnetASE.Delegations[0].ServiceName)" -ForegroundColor Gray
        
        if ($powerPlatformSubnetASE.ServiceAssociationLinks) {
            Write-Host "`n  Service Association Links:" -ForegroundColor White
            foreach ($link in $powerPlatformSubnetASE.ServiceAssociationLinks) {
                Write-Host "    - Name: $($link.Name)" -ForegroundColor Gray
                Write-Host "      Linked Resource: $($link.LinkedResourceType)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  ⚠ No service association links found" -ForegroundColor Yellow
        }
    } else {
        Write-Host "`n✗ West US Subnet is NOT delegated" -ForegroundColor Red
    }
    
} catch {
    Write-Host "✗ Error checking subnet delegations: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n[4] Checking Power Platform Connection..." -ForegroundColor Yellow
try {
    # Try to get Power Apps management instances
    Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction SilentlyContinue
    
    if (Get-Module -Name Microsoft.PowerApps.Administration.PowerShell) {
        Write-Host "✓ Power Apps module available" -ForegroundColor Green
        
        try {
            $env = Get-AdminPowerAppEnvironment -EnvironmentName $powerPlatformEnvironmentId -ErrorAction Stop
            Write-Host "✓ Environment found via Power Apps cmdlets!" -ForegroundColor Green
            Write-Host "`nEnvironment Details:" -ForegroundColor White
            Write-Host "  Display Name: $($env.DisplayName)" -ForegroundColor Gray
            Write-Host "  Environment Name: $($env.EnvironmentName)" -ForegroundColor Gray
            Write-Host "  Location: $($env.Location)" -ForegroundColor Gray
            Write-Host "  Environment Type: $($env.EnvironmentType)" -ForegroundColor Gray
            Write-Host "  Is Default: $($env.IsDefault)" -ForegroundColor Gray
        } catch {
            Write-Host "⚠ Could not retrieve environment via Power Apps cmdlets" -ForegroundColor Yellow
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "⚠ Power Apps module not available" -ForegroundColor Yellow
        Write-Host "  To install: Install-Module -Name Microsoft.PowerApps.Administration.PowerShell" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "⚠ Error checking Power Platform connection: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n[5] Wait and Retry Test..." -ForegroundColor Yellow
Write-Host "Sometimes the service needs a moment to sync. Waiting 10 seconds..." -ForegroundColor Gray
Start-Sleep -Seconds 10

Write-Host "`nRetrying Get-EnvironmentRegion..." -ForegroundColor Cyan
try {
    $finalResult = Get-EnvironmentRegion -EnvironmentId $powerPlatformEnvironmentId -ErrorAction Stop
    Write-Host "✓✓✓ SUCCESS! Environment Region: $finalResult ✓✓✓" -ForegroundColor Green -BackgroundColor Black
} catch {
    Write-Host "✗ Still failing: $($_.Exception.Message)" -ForegroundColor Red
    
    # Parse the correlation ID from error
    if ($_.Exception.Message -match 'Correlation ID: ([a-f0-9\-]+)') {
        $correlationId = $Matches[1]
        Write-Host "`n📋 Correlation ID for Microsoft Support: $correlationId" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Recommendations:" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n1. If the environment shows 'Succeeded' in Admin Center but still fails here:" -ForegroundColor White
Write-Host "   - The operation might need more propagation time (can take up to 30 minutes)" -ForegroundColor Gray
Write-Host "   - Try running this script again in 10-15 minutes" -ForegroundColor Gray

Write-Host "`n2. Verify the correct Environment ID:" -ForegroundColor White
Write-Host "   - Go to Power Platform Admin Center" -ForegroundColor Gray
Write-Host "   - Select your environment" -ForegroundColor Gray
Write-Host "   - Copy the Environment ID from the details pane" -ForegroundColor Gray
Write-Host "   - Ensure it matches: $powerPlatformEnvironmentId" -ForegroundColor Gray

Write-Host "`n3. Check if environment is in the correct region:" -ForegroundColor White
Write-Host "   - VNet integration requires environment and VNets in compatible regions" -ForegroundColor Gray
Write-Host "   - Your VNets are in: eastus, westus" -ForegroundColor Gray

Write-Host "`n4. If problem persists, contact Microsoft Support with:" -ForegroundColor White
Write-Host "   - Environment ID: $powerPlatformEnvironmentId" -ForegroundColor Gray
Write-Host "   - Enterprise Policy ID: $enterprisePolicyResourceId" -ForegroundColor Gray
Write-Host "   - Any correlation IDs from error messages" -ForegroundColor Gray

Write-Host "`n========================================`n" -ForegroundColor Cyan
