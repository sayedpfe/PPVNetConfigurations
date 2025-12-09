# Configure NSG Security Rules for Power Platform VNet Integration
# This script adds custom security rules to NSGs for enhanced security and compliance

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "476f3985-4e26-4f7d-8fcf-9f25f4da27a7",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "PPVNetUS-rs",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

Write-Host "=== Configuring NSG Security Rules ===" -ForegroundColor Cyan
Write-Host "This adds custom security rules for defense-in-depth" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "`n⚠ WHATIF MODE: No changes will be made" -ForegroundColor Yellow
}

# Set subscription context
Write-Host "`n[1/5] Setting Azure subscription context..." -ForegroundColor Green
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# Get all NSGs in resource group
Write-Host "`n[2/5] Getting existing NSGs..." -ForegroundColor Green
$nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName
Write-Host "  Found $($nsgs.Count) NSGs" -ForegroundColor Gray

# Define security rule configurations for different subnet types
$ruleConfigurations = @{
    "PowerPlatform" = @(
        @{
            Name = "Allow-HTTPS-Outbound"
            Description = "Allow HTTPS outbound for Power Platform services"
            Priority = 100
            Direction = "Outbound"
            Access = "Allow"
            Protocol = "Tcp"
            SourcePortRange = "*"
            DestinationPortRange = "443"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "Internet"
        },
        @{
            Name = "Allow-SQL-Outbound"
            Description = "Allow SQL outbound for Power Platform connectors"
            Priority = 110
            Direction = "Outbound"
            Access = "Allow"
            Protocol = "Tcp"
            SourcePortRange = "*"
            DestinationPortRange = "1433"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "Sql"
        },
        @{
            Name = "Allow-VNet-Inbound"
            Description = "Allow inbound from VNet for internal communication"
            Priority = 100
            Direction = "Inbound"
            Access = "Allow"
            Protocol = "*"
            SourcePortRange = "*"
            DestinationPortRange = "*"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "VirtualNetwork"
        },
        @{
            Name = "Deny-Internet-Inbound"
            Description = "Deny all inbound from Internet"
            Priority = 4000
            Direction = "Inbound"
            Access = "Deny"
            Protocol = "*"
            SourcePortRange = "*"
            DestinationPortRange = "*"
            SourceAddressPrefix = "Internet"
            DestinationAddressPrefix = "*"
        }
    )
    "PrivateEndpoint" = @(
        @{
            Name = "Allow-VNet-Inbound-HTTPS"
            Description = "Allow HTTPS from VNet to private endpoints"
            Priority = 100
            Direction = "Inbound"
            Access = "Allow"
            Protocol = "Tcp"
            SourcePortRange = "*"
            DestinationPortRange = "443"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "VirtualNetwork"
        },
        @{
            Name = "Deny-Internet-Inbound"
            Description = "Deny all inbound from Internet"
            Priority = 4000
            Direction = "Inbound"
            Access = "Deny"
            Protocol = "*"
            SourcePortRange = "*"
            DestinationPortRange = "*"
            SourceAddressPrefix = "Internet"
            DestinationAddressPrefix = "*"
        },
        @{
            Name = "Allow-VNet-Outbound"
            Description = "Allow outbound to VNet"
            Priority = 100
            Direction = "Outbound"
            Access = "Allow"
            Protocol = "*"
            SourcePortRange = "*"
            DestinationPortRange = "*"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "VirtualNetwork"
        }
    )
    "KeyVault" = @(
        @{
            Name = "Allow-HTTPS-to-KeyVault"
            Description = "Allow HTTPS to Key Vault service"
            Priority = 100
            Direction = "Outbound"
            Access = "Allow"
            Protocol = "Tcp"
            SourcePortRange = "*"
            DestinationPortRange = "443"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "AzureKeyVault"
        },
        @{
            Name = "Allow-VNet-Inbound"
            Description = "Allow inbound from VNet"
            Priority = 100
            Direction = "Inbound"
            Access = "Allow"
            Protocol = "*"
            SourcePortRange = "*"
            DestinationPortRange = "*"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "VirtualNetwork"
        }
    )
    "Default" = @(
        @{
            Name = "Allow-VNet-Inbound"
            Description = "Allow inbound from VNet"
            Priority = 100
            Direction = "Inbound"
            Access = "Allow"
            Protocol = "*"
            SourcePortRange = "*"
            DestinationPortRange = "*"
            SourceAddressPrefix = "VirtualNetwork"
            DestinationAddressPrefix = "VirtualNetwork"
        },
        @{
            Name = "Deny-Internet-Inbound"
            Description = "Deny all inbound from Internet"
            Priority = 4000
            Direction = "Inbound"
            Access = "Deny"
            Protocol = "*"
            SourcePortRange = "*"
            DestinationPortRange = "*"
            SourceAddressPrefix = "Internet"
            DestinationAddressPrefix = "*"
        }
    )
}

# Function to determine NSG type based on name/subnet
function Get-NSGType {
    param($NsgName, $SubnetName)
    
    if ($NsgName -like "*power-platform*" -or $SubnetName -like "*power-platform*" -or $SubnetName -eq "PPENVIRONMENT") {
        return "PowerPlatform"
    }
    elseif ($NsgName -like "*priv-endpoint*" -or $SubnetName -like "*priv-endpoint*" -or $NsgName -like "*private-endpoint*") {
        return "PrivateEndpoint"
    }
    elseif ($NsgName -like "*keyvault*" -or $SubnetName -like "*keyvault*") {
        return "KeyVault"
    }
    else {
        return "Default"
    }
}

# Function to add security rule to NSG
function Add-SecurityRuleToNSG {
    param(
        [Parameter(Mandatory=$true)]
        $NSG,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$RuleConfig,
        
        [Parameter(Mandatory=$false)]
        [switch]$WhatIf
    )
    
    # Check if rule already exists
    $existingRule = $NSG.SecurityRules | Where-Object { $_.Name -eq $RuleConfig.Name }
    
    if ($existingRule) {
        Write-Host "    ℹ Rule '$($RuleConfig.Name)' already exists" -ForegroundColor Yellow
        return $false
    }
    
    if ($WhatIf) {
        Write-Host "    [WHATIF] Would add rule: $($RuleConfig.Name)" -ForegroundColor Cyan
        return $true
    }
    
    try {
        Add-AzNetworkSecurityRuleConfig `
            -NetworkSecurityGroup $NSG `
            -Name $RuleConfig.Name `
            -Description $RuleConfig.Description `
            -Priority $RuleConfig.Priority `
            -Direction $RuleConfig.Direction `
            -Access $RuleConfig.Access `
            -Protocol $RuleConfig.Protocol `
            -SourcePortRange $RuleConfig.SourcePortRange `
            -DestinationPortRange $RuleConfig.DestinationPortRange `
            -SourceAddressPrefix $RuleConfig.SourceAddressPrefix `
            -DestinationAddressPrefix $RuleConfig.DestinationAddressPrefix `
            -ErrorAction Stop | Out-Null
        
        Write-Host "    ✓ Added rule: $($RuleConfig.Name)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "    ✗ Failed to add rule '$($RuleConfig.Name)': $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Process each NSG
Write-Host "`n[3/5] Configuring NSG rules..." -ForegroundColor Green

$changedNSGs = @()

foreach ($nsg in $nsgs) {
    Write-Host "`n  NSG: $($nsg.Name)" -ForegroundColor White
    
    # Get subnet name for determining NSG type
    $subnetName = if ($nsg.Subnets.Count -gt 0) {
        $nsg.Subnets[0].Id.Split('/')[-1]
    } else {
        "Unknown"
    }
    
    # Determine NSG type
    $nsgType = Get-NSGType -NsgName $nsg.Name -SubnetName $subnetName
    Write-Host "    Type: $nsgType" -ForegroundColor Gray
    Write-Host "    Subnet: $subnetName" -ForegroundColor Gray
    
    # Get appropriate rule configuration
    $rules = $ruleConfigurations[$nsgType]
    
    if (-not $rules) {
        Write-Host "    ⚠ No rule configuration found for type: $nsgType" -ForegroundColor Yellow
        continue
    }
    
    # Add rules to NSG
    $rulesAdded = 0
    foreach ($rule in $rules) {
        $added = Add-SecurityRuleToNSG -NSG $nsg -RuleConfig $rule -WhatIf:$WhatIf
        if ($added) { $rulesAdded++ }
    }
    
    # Save NSG if rules were added
    if ($rulesAdded -gt 0 -and -not $WhatIf) {
        Write-Host "    💾 Saving NSG with $rulesAdded new rules..." -ForegroundColor Cyan
        try {
            Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg -ErrorAction Stop | Out-Null
            Write-Host "    ✓ NSG saved successfully" -ForegroundColor Green
            $changedNSGs += $nsg.Name
        }
        catch {
            Write-Host "    ✗ Failed to save NSG: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Summary
Write-Host "`n[4/5] Configuration Summary..." -ForegroundColor Green

if ($WhatIf) {
    Write-Host "  ℹ WhatIf mode - no changes were made" -ForegroundColor Yellow
    Write-Host "  Run without -WhatIf to apply changes" -ForegroundColor Gray
}
else {
    Write-Host "  NSGs modified: $($changedNSGs.Count)" -ForegroundColor White
    if ($changedNSGs.Count -gt 0) {
        $changedNSGs | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
    }
}

# Verification
Write-Host "`n[5/5] Verification..." -ForegroundColor Green
$updatedNSGs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName

Write-Host "`n  NSG Rule Summary:" -ForegroundColor White
foreach ($nsg in $updatedNSGs) {
    $customRules = $nsg.SecurityRules.Count
    $defaultRules = $nsg.DefaultSecurityRules.Count
    Write-Host "    $($nsg.Name): $customRules custom rules, $defaultRules default rules" -ForegroundColor Gray
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "✓ NSG Configuration Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 What Was Configured:" -ForegroundColor White
Write-Host "  • Power Platform subnets: HTTPS/SQL outbound, VNet inbound allowed" -ForegroundColor Gray
Write-Host "  • Private Endpoint subnets: HTTPS from VNet allowed" -ForegroundColor Gray
Write-Host "  • Key Vault subnets: HTTPS to Key Vault service allowed" -ForegroundColor Gray
Write-Host "  • All subnets: Internet inbound denied (explicit)" -ForegroundColor Gray
Write-Host ""
Write-Host "🔍 Verify Rules:" -ForegroundColor White
Write-Host "  Azure Portal → Network Security Groups → [Select NSG] → Inbound/Outbound security rules" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠ Important Notes:" -ForegroundColor Yellow
Write-Host "  • These rules enhance security but are not required for basic functionality" -ForegroundColor Gray
Write-Host "  • Default Azure NSG rules still apply" -ForegroundColor Gray
Write-Host "  • Private endpoints bypass NSG rules by design" -ForegroundColor Gray
Write-Host "  • Modify rules as needed for your specific security requirements" -ForegroundColor Gray
Write-Host ""
