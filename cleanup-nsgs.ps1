# Clean Up Network Security Groups
# This script helps remove unnecessary NSGs or disassociate them from subnets

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = "476f3985-4e26-4f7d-8fcf-9f25f4da27a7",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "PPVNetUS-rs",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("RemoveUnassociated", "DisassociateAll", "RemoveAll", "Interactive")]
    [string]$CleanupMode = "Interactive",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

Write-Host "=== Network Security Group Cleanup ===" -ForegroundColor Cyan
Write-Host "This script helps clean up NSGs in your resource group" -ForegroundColor Yellow

if ($WhatIf) {
    Write-Host "`n⚠ WHATIF MODE: No changes will be made" -ForegroundColor Yellow
}

# Set subscription context
Write-Host "`n[1/4] Setting Azure subscription context..." -ForegroundColor Green
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

# Get all NSGs
Write-Host "`n[2/4] Analyzing Network Security Groups..." -ForegroundColor Green
$nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName

Write-Host "  Total NSGs found: $($nsgs.Count)" -ForegroundColor White

# Categorize NSGs
$associatedNSGs = @()
$unassociatedNSGs = @()
$emptyNSGs = @()

foreach ($nsg in $nsgs) {
    $hasSubnets = $nsg.Subnets.Count -gt 0
    $hasNics = $nsg.NetworkInterfaces.Count -gt 0
    $hasCustomRules = $nsg.SecurityRules.Count -gt 0
    
    $nsgInfo = [PSCustomObject]@{
        NSG = $nsg
        Name = $nsg.Name
        Location = $nsg.Location
        SubnetCount = $nsg.Subnets.Count
        NicCount = $nsg.NetworkInterfaces.Count
        CustomRules = $nsg.SecurityRules.Count
        SubnetNames = ($nsg.Subnets | ForEach-Object { $_.Id.Split('/')[-1] }) -join ', '
        IsAssociated = ($hasSubnets -or $hasNics)
        IsEmpty = (-not $hasCustomRules)
    }
    
    if ($nsgInfo.IsAssociated) {
        $associatedNSGs += $nsgInfo
    }
    else {
        $unassociatedNSGs += $nsgInfo
    }
    
    if ($nsgInfo.IsEmpty) {
        $emptyNSGs += $nsgInfo
    }
}

# Display analysis
Write-Host "`n  📊 Analysis Results:" -ForegroundColor White
Write-Host "    Associated NSGs (attached to subnets/NICs): $($associatedNSGs.Count)" -ForegroundColor Gray
Write-Host "    Unassociated NSGs (not attached): $($unassociatedNSGs.Count)" -ForegroundColor Gray
Write-Host "    NSGs with no custom rules: $($emptyNSGs.Count)" -ForegroundColor Gray

# Display detailed information
if ($associatedNSGs.Count -gt 0) {
    Write-Host "`n  Associated NSGs:" -ForegroundColor Cyan
    foreach ($nsgInfo in $associatedNSGs) {
        $ruleInfo = if ($nsgInfo.CustomRules -gt 0) { "$($nsgInfo.CustomRules) custom rules" } else { "no custom rules" }
        Write-Host "    ✓ $($nsgInfo.Name)" -ForegroundColor Green
        Write-Host "      Subnets: $($nsgInfo.SubnetNames)" -ForegroundColor Gray
        Write-Host "      Rules: $ruleInfo" -ForegroundColor Gray
    }
}

if ($unassociatedNSGs.Count -gt 0) {
    Write-Host "`n  Unassociated NSGs (Safe to Remove):" -ForegroundColor Yellow
    foreach ($nsgInfo in $unassociatedNSGs) {
        Write-Host "    ⚠ $($nsgInfo.Name)" -ForegroundColor Yellow
        Write-Host "      Status: Not attached to any subnet or NIC" -ForegroundColor Gray
    }
}

# Cleanup operations
Write-Host "`n[3/4] Cleanup Operations..." -ForegroundColor Green

$removedNSGs = @()
$disassociatedSubnets = @()

switch ($CleanupMode) {
    "RemoveUnassociated" {
        Write-Host "  Mode: Remove unassociated NSGs only" -ForegroundColor White
        
        if ($unassociatedNSGs.Count -eq 0) {
            Write-Host "    ℹ No unassociated NSGs to remove" -ForegroundColor Yellow
        }
        else {
            foreach ($nsgInfo in $unassociatedNSGs) {
                if ($WhatIf) {
                    Write-Host "    [WHATIF] Would remove: $($nsgInfo.Name)" -ForegroundColor Cyan
                }
                else {
                    try {
                        Remove-AzNetworkSecurityGroup -Name $nsgInfo.Name -ResourceGroupName $ResourceGroupName -Force -ErrorAction Stop
                        Write-Host "    ✓ Removed: $($nsgInfo.Name)" -ForegroundColor Green
                        $removedNSGs += $nsgInfo.Name
                    }
                    catch {
                        Write-Host "    ✗ Failed to remove $($nsgInfo.Name): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }
    }
    
    "DisassociateAll" {
        Write-Host "  Mode: Disassociate all NSGs from subnets" -ForegroundColor White
        
        foreach ($nsgInfo in $associatedNSGs) {
            if ($nsgInfo.SubnetCount -eq 0) { continue }
            
            foreach ($subnetRef in $nsgInfo.NSG.Subnets) {
                $vnetName = $subnetRef.Id.Split('/')[-3]
                $subnetName = $subnetRef.Id.Split('/')[-1]
                
                if ($WhatIf) {
                    Write-Host "    [WHATIF] Would disassociate NSG from: $vnetName/$subnetName" -ForegroundColor Cyan
                }
                else {
                    try {
                        # Get VNet and subnet
                        $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
                        $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName -ErrorAction Stop
                        
                        # Remove NSG association
                        $subnet.NetworkSecurityGroup = $null
                        Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null
                        
                        Write-Host "    ✓ Disassociated NSG from: $vnetName/$subnetName" -ForegroundColor Green
                        $disassociatedSubnets += "$vnetName/$subnetName"
                    }
                    catch {
                        Write-Host "    ✗ Failed to disassociate from $vnetName/$subnetName: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }
    }
    
    "RemoveAll" {
        Write-Host "  Mode: Remove all NSGs (WARNING: Use with caution)" -ForegroundColor Red
        Write-Host "    ⚠ This will disassociate and delete ALL NSGs" -ForegroundColor Yellow
        
        # First disassociate all
        foreach ($nsgInfo in $associatedNSGs) {
            if ($nsgInfo.SubnetCount -eq 0) { continue }
            
            foreach ($subnetRef in $nsgInfo.NSG.Subnets) {
                $vnetName = $subnetRef.Id.Split('/')[-3]
                $subnetName = $subnetRef.Id.Split('/')[-1]
                
                if (-not $WhatIf) {
                    try {
                        $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
                        $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName -ErrorAction Stop
                        $subnet.NetworkSecurityGroup = $null
                        Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null
                        $disassociatedSubnets += "$vnetName/$subnetName"
                    }
                    catch {
                        Write-Host "    ✗ Failed to disassociate from $vnetName/$subnetName" -ForegroundColor Red
                    }
                }
            }
        }
        
        # Then remove all NSGs
        foreach ($nsg in $nsgs) {
            if ($WhatIf) {
                Write-Host "    [WHATIF] Would remove: $($nsg.Name)" -ForegroundColor Cyan
            }
            else {
                try {
                    Remove-AzNetworkSecurityGroup -Name $nsg.Name -ResourceGroupName $ResourceGroupName -Force -ErrorAction Stop
                    Write-Host "    ✓ Removed: $($nsg.Name)" -ForegroundColor Green
                    $removedNSGs += $nsg.Name
                }
                catch {
                    Write-Host "    ✗ Failed to remove $($nsg.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
    
    "Interactive" {
        Write-Host "  Mode: Interactive cleanup" -ForegroundColor White
        Write-Host ""
        Write-Host "  Available Options:" -ForegroundColor Cyan
        Write-Host "    1. Remove unassociated NSGs only (safe)" -ForegroundColor Gray
        Write-Host "    2. Disassociate NSGs from all subnets" -ForegroundColor Gray
        Write-Host "    3. Remove all NSGs (disassociate + delete)" -ForegroundColor Gray
        Write-Host "    4. Cancel" -ForegroundColor Gray
        Write-Host ""
        
        $choice = Read-Host "  Select option (1-4)"
        
        switch ($choice) {
            "1" {
                Write-Host "`n  Removing unassociated NSGs..." -ForegroundColor Green
                foreach ($nsgInfo in $unassociatedNSGs) {
                    try {
                        Remove-AzNetworkSecurityGroup -Name $nsgInfo.Name -ResourceGroupName $ResourceGroupName -Force -ErrorAction Stop
                        Write-Host "    ✓ Removed: $($nsgInfo.Name)" -ForegroundColor Green
                        $removedNSGs += $nsgInfo.Name
                    }
                    catch {
                        Write-Host "    ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
            "2" {
                Write-Host "`n  Are you sure you want to disassociate NSGs from all subnets? (yes/no)" -ForegroundColor Yellow
                $confirm = Read-Host
                if ($confirm -eq "yes") {
                    # Run DisassociateAll logic
                    Write-Host "  Processing..." -ForegroundColor Green
                    Write-Host "    ℹ Use -CleanupMode DisassociateAll for batch operation" -ForegroundColor Yellow
                }
            }
            "3" {
                Write-Host "`n  ⚠ WARNING: This will remove ALL NSGs!" -ForegroundColor Red
                Write-Host "  Type 'DELETE ALL NSGs' to confirm:" -ForegroundColor Yellow
                $confirm = Read-Host
                if ($confirm -eq "DELETE ALL NSGs") {
                    Write-Host "  Processing..." -ForegroundColor Green
                    Write-Host "    ℹ Use -CleanupMode RemoveAll for batch operation" -ForegroundColor Yellow
                }
                else {
                    Write-Host "    Cancelled" -ForegroundColor Gray
                }
            }
            default {
                Write-Host "    Cancelled" -ForegroundColor Gray
            }
        }
    }
}

# Summary
Write-Host "`n[4/4] Cleanup Summary..." -ForegroundColor Green

if ($WhatIf) {
    Write-Host "  ℹ WhatIf mode - no changes were made" -ForegroundColor Yellow
    Write-Host "  Run without -WhatIf to apply changes" -ForegroundColor Gray
}
else {
    Write-Host "  NSGs removed: $($removedNSGs.Count)" -ForegroundColor White
    if ($removedNSGs.Count -gt 0) {
        $removedNSGs | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
    }
    
    Write-Host "  Subnets disassociated: $($disassociatedSubnets.Count)" -ForegroundColor White
    if ($disassociatedSubnets.Count -gt 0) {
        $disassociatedSubnets | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
    }
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "✓ NSG Cleanup Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Usage Examples:" -ForegroundColor White
Write-Host "  # Preview cleanup (safe)" -ForegroundColor Gray
Write-Host "  .\cleanup-nsgs.ps1 -WhatIf" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # Remove only unassociated NSGs" -ForegroundColor Gray
Write-Host "  .\cleanup-nsgs.ps1 -CleanupMode RemoveUnassociated" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # Disassociate all NSGs from subnets" -ForegroundColor Gray
Write-Host "  .\cleanup-nsgs.ps1 -CleanupMode DisassociateAll" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # Remove all NSGs (careful!)" -ForegroundColor Gray
Write-Host "  .\cleanup-nsgs.ps1 -CleanupMode RemoveAll" -ForegroundColor Cyan
Write-Host ""
