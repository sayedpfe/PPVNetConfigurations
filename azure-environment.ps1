# Azure PowerShell script to set up resources for Power App integration

# https://forwardforever.com/setting-up-power-platform-vnet-integration/
# Connect to Azure
Connect-AzAccount

# Set the subscription context
$subscriptionId = (Get-AzContext).Subscription.Id
Set-AzContext -SubscriptionId $subscriptionId

# Variables
$resourceGroupName = "PPVNetUS-rs"
$location = "eastus"
$keyVaultName = "kv-power-app-2025"
$secretName = "shippingCredentials"
$secretValue = "suP3rSecr3t!"

# Create a new resource group
Write-Host "Creating resource group $resourceGroupName in $location..."
New-AzResourceGroup -Name $resourceGroupName -Location $location

# Create a new key vault
Write-Host "Creating key vault $keyVaultName..."
$keyVaultParams = @{
    Name = $keyVaultName
    ResourceGroupName = $resourceGroupName
    Location = $location
    Sku = "Standard"
    EnabledForDeployment = $true
    EnabledForTemplateDeployment = $true
    EnabledForDiskEncryption = $true
    DisableRbacAuthorization = $true
}
New-AzKeyVault @keyVaultParams

# Convert secret to secure string
$secureSecretValue = ConvertTo-SecureString -String $secretValue -AsPlainText -Force

# Add a secret to the key vault
Write-Host "Adding secret $secretName to key vault..."
Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secureSecretValue

Write-Host "Setup completed successfully!"

# Grant access to key vault secret for specific user
$userEmail = "admin@M365CPI90282478.onmicrosoft.com"
$userObjectId = (Get-AzADUser -UserPrincipalName $userEmail).Id

# Check if user exists
if ($null -eq $userObjectId) {
    Write-Error "User $userEmail not found. Please verify the email address."
    exit
}

# Grant secret permissions to the user
# Key Vault permissions for secrets: get, list, set, delete, backup, restore, recover, purge
Set-AzKeyVaultAccessPolicy -VaultName $keyVaultName `
                          -ResourceGroupName $resourceGroupName `
                          -ObjectId $userObjectId `
                          -PermissionsToSecrets get,list

Write-Host "Access granted to $userEmail for secrets in key vault $keyVaultName"

####
# test power pages connectivity to key vault
# https://supportportal-9cda.powerappsportals.com/shipping-credentials/

###########################
#### Power Platform Vnet Injection

# create vnet and subnet /24 in australiaeast
$vNetRegionAE = "eastus"
$vNetNameAE = "vnet-power-platform-test-eus"
$vNetAddressPrefixAE = "192.168.0.0/16"
$vNetSubnetNameAE = "subnet-power-platform-test-eus"
$vNetSubnetAddressPrefixAE = "192.168.1.0/24"
$vNetAE = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName `
    -Location $vNetRegionAE `
    -Name $vNetNameAE `
    -AddressPrefix $vNetAddressPrefixAE
$vNetSubnetAE = Add-AzVirtualNetworkSubnetConfig -Name $vNetSubnetNameAE `
    -AddressPrefix $vNetSubnetAddressPrefixAE `
    -VirtualNetwork $vNetAE
$vNetAE | Set-AzVirtualNetwork

# create vnet and subnet /24 in australiasoutheast
$vNetRegionASE = "westus"
$vNetNameASE = "vnet-power-platform-test-wus"
$vNetAddressPrefixASE = "192.169.0.0/16"
$vNetSubnetNameASE = "subnet-power-platform-test-wus"
$vNetSubnetAddressPrefixASE = "192.169.1.0/24"
$vNetASE = New-AzVirtualNetwork -ResourceGroupName $resourceGroupName `
    -Location $vNetRegionASE `
    -Name $vNetNameASE `
    -AddressPrefix $vNetAddressPrefixASE
$vNetSubnetASE = Add-AzVirtualNetworkSubnetConfig -Name $vNetSubnetNameASE `
    -AddressPrefix $vNetSubnetAddressPrefixASE `
    -VirtualNetwork $vNetASE
$vNetASE | Set-AzVirtualNetwork

# register the subscription for Microsoft.PowerPlatform
./PowerApps-Samples-Sparse/powershell/enterprisePolicies/SetupSubscriptionForPowerPlatform.ps1

# delegate the subnet to Power Platform Enterprise Policies
./powershell\enterprisePolicies\SubnetInjection\SetupVnetForSubnetDelegation.ps1

# create the vnet injection enterprise policy
$vnetIdAE = $vNetAE.Id
$vnetIdASE = $vNetASE.Id
$enterprisePolicyName = "Power-Platform-Test-Vnet-Injection-Enterprise-Policy"
./powershell\enterprisePolicies\SubnetInjection\CreateSubnetInjectionEnterprisePolicy.ps1


# assign reader role to Power Platform Admin https://learn.microsoft.com/en-us/power-platform/admin/customer-managed-key#grant-reader-role-to-a-power-platform-administrator
$powerPlatformAdminUserId = "1a5bfda8-d02c-476a-81ef-f9ee2367c239"
$enterprisePolicyResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.PowerPlatform/enterprisePolicies/$enterprisePolicyName"
New-AzRoleAssignment -ObjectId $powerPlatformAdminUserId -RoleDefinitionName Reader -Scope $enterprisePolicyResourceId

# configure power platform environment
./PowerApps-Samples-Sparse/powershell/enterprisePolicies/InstallPowerAppsCmdlets.ps1
 
$powerPlaftformEnvironmentId = "50f3edf1-abe7-e31d-9602-dc56f4f3e404"
./powershell\enterprisePolicies\SubnetInjection\NewSubnetInjection.ps1


#########
# Create Private Endpoint for Key Vault
# Define variables for private endpoint subnet
$privEndpointSubnetName = "subnet-priv-endpoint-ae"
$privEndpointSubnetAddressPrefix = "192.168.2.0/24"
$privDnsZoneName = "privatelink.vaultcore.azure.net"
$privEndpointName = "$keyVaultName-private-endpoint"

Write-Host "Creating subnet for private endpoint..."
# Get the virtual network
$vNet = Get-AzVirtualNetwork -Name $vNetNameAE -ResourceGroupName $resourceGroupName

# Add the private endpoint subnet
Add-AzVirtualNetworkSubnetConfig -Name $privEndpointSubnetName `
    -AddressPrefix $privEndpointSubnetAddressPrefix `
    -VirtualNetwork $vNet | Set-AzVirtualNetwork

# Get the updated virtual network and the subnet
$vNet = Get-AzVirtualNetwork -Name $vNetNameAE -ResourceGroupName $resourceGroupName
$privEndpointSubnet = Get-AzVirtualNetworkSubnetConfig -Name $privEndpointSubnetName -VirtualNetwork $vNet

Write-Host "Creating private DNS zone..."
# Create the private DNS zone
$privateDnsZone = New-AzPrivateDnsZone -ResourceGroupName $resourceGroupName `
    -Name $privDnsZoneName

Write-Host "Creating virtual network link..."
# Create DNS network link
$vNetLinkName = "$vNetNameAE-link"
$vNetLink = New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName `
    -ZoneName $privDnsZoneName `
    -Name $vNetLinkName `
    -VirtualNetworkId $vNet.Id

$vNet = Get-AzVirtualNetwork -Name $vNetNameASE -ResourceGroupName $resourceGroupName
$vNetLinkName = "$vNetNameASE-link"
$vNetLink = New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName `
    -ZoneName $privDnsZoneName `
    -Name $vNetLinkName `
    -VirtualNetworkId $vNet.Id

# vnet peering of vnetAE and vnetASE
$vNetAE = Get-AzVirtualNetwork -Name $vNetNameAE -ResourceGroupName $resourceGroupName
$vNetASE = Get-AzVirtualNetwork -Name $vNetNameASE -ResourceGroupName $resourceGroupName
$vNetAE | Add-AzVirtualNetworkPeering -Name "$vNetNameAE-to-$vNetNameASE" `
    -RemoteVirtualNetworkId $vNetASE.Id
$vNetASE | Add-AzVirtualNetworkPeering -Name "$vNetNameASE-to-$vNetNameAE" `
    -RemoteVirtualNetworkId $vNetAE.Id


Write-Host "Creating private endpoint for Key Vault $keyVaultName..."
# Get the Key Vault resource
$keyVault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName

# Create private endpoint
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$privEndpointName-connection" `
    -PrivateLinkServiceId $keyVault.ResourceId `
    -GroupId "vault"

$privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $resourceGroupName `
    -Name $privEndpointName `
    -Location $vNetRegionAE `
    -Subnet $privEndpointSubnet `
    -PrivateLinkServiceConnection $privateEndpointConnection

Write-Host "Creating private DNS record..."
# Get the private IP address of the private endpoint
$privateEndpoint = Get-AzPrivateEndpoint -Name $privEndpointName -ResourceGroupName $resourceGroupName
$networkInterface = Get-AzNetworkInterface -ResourceId ($privateEndpoint.NetworkInterfaces[0].Id)
$privateIpAddress = $networkInterface.IpConfigurations[0].PrivateIpAddress

# Create A record in the private DNS zone
$recordSet = New-AzPrivateDnsRecordSet -ResourceGroupName $resourceGroupName `
    -ZoneName $privDnsZoneName `
    -Name $keyVaultName `
    -RecordType A `
    -Ttl 3600

Add-AzPrivateDnsRecordConfig -RecordSet $recordSet -Ipv4Address $privateIpAddress

Set-AzPrivateDnsRecordSet -RecordSet $recordSet

Write-Host "Private endpoint for Key Vault created successfully."

# Create dedicated subnets for Key Vault network rules (separate from Power Platform delegated subnets)
Write-Host "Creating dedicated Key Vault access subnets..."
$kvSubnetNameAE = "subnet-keyvault-eus"
$kvSubnetAddressPrefixAE = "192.168.3.0/24"
$kvSubnetNameASE = "subnet-keyvault-wus"
$kvSubnetAddressPrefixASE = "192.169.3.0/24"

# Get the virtual networks
$vNetAE = Get-AzVirtualNetwork -Name $vNetNameAE -ResourceGroupName $resourceGroupName
$vNetASE = Get-AzVirtualNetwork -Name $vNetNameASE -ResourceGroupName $resourceGroupName

# Add Key Vault subnets to both VNets with service endpoints
Write-Host "Adding Key Vault subnet to East US VNet..."
Add-AzVirtualNetworkSubnetConfig -Name $kvSubnetNameAE `
    -AddressPrefix $kvSubnetAddressPrefixAE `
    -VirtualNetwork $vNetAE `
    -ServiceEndpoint @("Microsoft.KeyVault") | Set-AzVirtualNetwork

Write-Host "Adding Key Vault subnet to West US VNet..."
Add-AzVirtualNetworkSubnetConfig -Name $kvSubnetNameASE `
    -AddressPrefix $kvSubnetAddressPrefixASE `
    -VirtualNetwork $vNetASE `
    -ServiceEndpoint @("Microsoft.KeyVault") | Set-AzVirtualNetwork

# Get the updated virtual networks and subnet resource IDs
$vNetAE = Get-AzVirtualNetwork -Name $vNetNameAE -ResourceGroupName $resourceGroupName
$vNetASE = Get-AzVirtualNetwork -Name $vNetNameASE -ResourceGroupName $resourceGroupName
$kvSubnetAE = Get-AzVirtualNetworkSubnetConfig -Name $kvSubnetNameAE -VirtualNetwork $vNetAE
$kvSubnetASE = Get-AzVirtualNetworkSubnetConfig -Name $kvSubnetNameASE -VirtualNetwork $vNetASE

# Add network rules for the Key Vault subnets
Write-Host "Adding Key Vault network rules for dedicated subnets..."
Add-AzKeyVaultNetworkRule -VaultName $keyVaultName -VirtualNetworkResourceId $kvSubnetAE.Id
Add-AzKeyVaultNetworkRule -VaultName $keyVaultName -VirtualNetworkResourceId $kvSubnetASE.Id

# Set default action to Deny and bypass to AzureServices
Write-Host "Configuring Key Vault network rule set..."
Update-AzKeyVaultNetworkRuleSet -VaultName $keyVaultName -DefaultAction Deny -Bypass AzureServices

# Verify the network rules are applied
Write-Host "Verifying Key Vault network configuration..."
$keyVaultNetworkRules = (Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName).NetworkAcls
Write-Host "Default Action: $($keyVaultNetworkRules.DefaultAction)"
Write-Host "Bypass: $($keyVaultNetworkRules.Bypass)"
Write-Host "Virtual Network Rules: $($keyVaultNetworkRules.VirtualNetworkRules.Count) rules configured"

# disable public access to the key vault (do this after setting up network rules)
Write-Host "Disabling public access to Key Vault..."
Update-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName -PublicNetworkAccess Disabled

Write-Host "Key Vault $keyVaultName now allows access only from dedicated Key Vault subnets and private endpoint."

#########
# Troubleshooting and Verification
Write-Host "`n========== TROUBLESHOOTING SECTION =========="

# Verify Power Platform VNet injection was applied
Write-Host "`nVerifying Power Platform VNet Integration..."
Write-Host "Note: VNet integration can take several minutes to complete after applying the enterprise policy."
Write-Host "If you see 'Subnet information not found', wait 5-10 minutes and try again.`n"

# Check if the diagnostics module is available
try {
    Import-Module Microsoft.PowerPlatform.EnterprisePolicies -ErrorAction Stop
    Write-Host "✓ Microsoft.PowerPlatform.EnterprisePolicies module loaded successfully"
    
    # Try to get environment region (this will fail if VNet injection is not applied yet)
    try {
        Write-Host "`nChecking Power Platform environment region..."
        $envRegion = Get-EnvironmentRegion -EnvironmentId $powerPlaftformEnvironmentId
        Write-Host "✓ Environment Region: $envRegion"
        Write-Host "✓ VNet integration appears to be configured successfully!"
        
        # Additional verification
        Write-Host "`nEnvironment should be accessible from these regions:"
        Write-Host "  - $vNetRegionAE (East US)"
        Write-Host "  - $vNetRegionASE (West US)"
        
    } catch {
        Write-Warning "⚠ Cannot retrieve environment region information."
        Write-Warning "Error: $($_.Exception.Message)"
        Write-Host "`nPossible reasons:"
        Write-Host "  1. VNet injection is still being applied (can take 5-10 minutes)"
        Write-Host "  2. Enterprise policy was not successfully linked to the environment"
        Write-Host "  3. The environment ID is incorrect: $powerPlaftformEnvironmentId"
        Write-Host "`nTo check the status:"
        Write-Host "  1. Go to Power Platform Admin Center: https://admin.powerplatform.microsoft.com"
        Write-Host "  2. Navigate to Environments > [Your Environment] > History"
        Write-Host "  3. Verify the VNet injection operation shows 'Succeeded'"
        Write-Host "`nTo retry after waiting:"
        Write-Host "  Get-EnvironmentRegion -EnvironmentId '$powerPlaftformEnvironmentId'"
    }
    
} catch {
    Write-Warning "⚠ Microsoft.PowerPlatform.EnterprisePolicies module not found or could not be loaded."
    Write-Host "To install the module, run:"
    Write-Host "  Install-Module -Name Microsoft.PowerPlatform.EnterprisePolicies -Scope CurrentUser"
}

# Verify Azure resources
Write-Host "`n========== AZURE RESOURCES SUMMARY =========="
Write-Host "Resource Group: $resourceGroupName"
Write-Host "Location: $location"
Write-Host "`nKey Vault:"
Write-Host "  Name: $keyVaultName"
Write-Host "  Public Access: Disabled (accessible via private endpoint and VNet)"
Write-Host "`nVirtual Networks:"
Write-Host "  East US VNet: $vNetNameAE ($vNetAddressPrefixAE)"
Write-Host "    - Power Platform Subnet: $vNetSubnetNameAE ($vNetSubnetAddressPrefixAE)"
Write-Host "    - Private Endpoint Subnet: $privEndpointSubnetName ($privEndpointSubnetAddressPrefix)"
Write-Host "    - Key Vault Access Subnet: $kvSubnetNameAE ($kvSubnetAddressPrefixAE)"
Write-Host "  West US VNet: $vNetNameASE ($vNetAddressPrefixASE)"
Write-Host "    - Power Platform Subnet: $vNetSubnetNameASE ($vNetSubnetAddressPrefixASE)"
Write-Host "    - Key Vault Access Subnet: $kvSubnetNameASE ($kvSubnetAddressPrefixASE)"
Write-Host "`nEnterprise Policy:"
Write-Host "  Name: $enterprisePolicyName"
Write-Host "  Resource ID: $enterprisePolicyResourceId"
Write-Host "`nPower Platform Environment:"
Write-Host "  Environment ID: $powerPlaftformEnvironmentId"
Write-Host "`n============================================`n"

# cleanup (commented out for safety - uncomment when ready to delete)
# Write-Host "WARNING: Cleanup is commented out for safety."
# Write-Host "To delete all resources, uncomment the following line:"
# Write-Host "Remove-AzResourceGroup -Name $resourceGroupName -Force"
# Remove-AzResourceGroup -Name $resourceGroupName -Force