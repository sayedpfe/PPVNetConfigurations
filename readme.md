# Power Platform to Azure Secure Connectivity: Setup Guide

## Overview
This guide walks you through securely connecting your Power Platform environment to Azure resources (Key Vault, Storage Accounts, Azure SQL) using private networking and VNet integration. The solution includes automated PowerShell scripts for complete infrastructure deployment and configuration.

---

## Scenario
This solution enables you to:
- Set up Power Platform VNet integration with Azure resources
- Configure Azure Key Vault with private endpoint access
- Implement secure connectivity using dual-region VNet architecture
- Test and validate private network connectivity from Power Platform

---

## Prerequisites

### Required Software
- **PowerShell 7+** (recommended) or **PowerShell 5.1** for Windows
- **Azure PowerShell Module** (Az module)
  ```powershell
  Install-Module -Name Az -Repository PSGallery -Force -AllowClobber
  ```
- **Power Platform PowerShell Modules**
  ```powershell
  Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
  Install-Module -Name Microsoft.PowerPlatform.EnterprisePolicies -Scope CurrentUser
  ```

### Azure Requirements
- **Active Azure Subscription**
- **Power Platform Environment** (must be a Managed Environment)
- **Subscription Registration**: Microsoft.PowerPlatform resource provider must be registered

### Required Azure Permissions & Roles

To successfully run the `azure-environment.ps1` script, you need the following permissions:

#### Azure Subscription Level
- **Contributor** or **Owner** role on the subscription OR
- Custom role with these permissions:
  - `Microsoft.Resources/subscriptions/resourceGroups/*` (create/manage resource groups)
  - `Microsoft.Network/*` (create/manage VNets, subnets, peering, private endpoints)
  - `Microsoft.KeyVault/*` (create/manage Key Vault)
  - `Microsoft.PrivateDns/*` (create/manage private DNS zones)
  - `Microsoft.PowerPlatform/enterprisePolicies/*` (create/manage enterprise policies)
  - `Microsoft.Authorization/roleAssignments/write` (assign Reader role)

#### Power Platform Permissions
- **Power Platform Administrator** role (to configure environment VNet injection)
- **Environment Admin** role on the target Power Platform environment

#### Azure AD Permissions
- **User.Read.All** (to query user object IDs for Key Vault access policies)
- Or specific permissions to read user information in Azure AD

### Networking Requirements
- **Two Azure Regions**: Deploy VNets in two regions within the same Power Platform geography
  - Example: East US + West US (United States)
  - Example: Australia East + Australia Southeast (Australia)
- **VNet Address Space**: 
  - Primary VNet: /16 or larger (e.g., 192.168.0.0/16)
  - Secondary VNet: /16 or larger (e.g., 192.169.0.0/16)
- **Subnet Requirements**:
  - Power Platform delegated subnet: Minimum /27 (32 IPs) for dev/test, /26 (64 IPs) recommended for production
  - Private endpoint subnet: /27 or larger
  - Key Vault access subnet: /27 or larger
  - Subnet must be delegated to `Microsoft.PowerPlatform/enterprisePolicies`

### Power Platform Environment Requirements
- **Managed Environment**: The environment MUST be converted to a Managed Environment before VNet integration
  - Enable in Power Platform Admin Center: Environments > [Your Environment] > Settings > Enable Managed Environment
- **Environment Region**: Must be in a supported region that matches your VNet geography
- **Environment Type**: Production or Sandbox (default environments not supported)

### Supported Regions
Refer to the official documentation for supported Power Platform regions:
- [Power Platform VNet Support Overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions)

---

## Implementation Steps

### 1. Pre-Deployment Checklist

Before running the main setup script, complete these steps:

1. **Verify Azure Permissions**
   ```powershell
   # Connect to Azure
   Connect-AzAccount
   
   # Verify subscription access
   Get-AzSubscription
   
   # Set the correct subscription context
   Set-AzContext -SubscriptionId "<your-subscription-id>"
   
   # Verify you have necessary permissions
   Get-AzRoleAssignment -SignInName "<your-email>" -Scope "/subscriptions/<subscription-id>"
   ```

2. **Install Required PowerShell Modules**
   ```powershell
   # Run the module installation script
   .\powershell\enterprisePolicies\InstallPowerAppsCmdlets.ps1
   ```

3. **Ensure Power Platform Environment is Managed**
   - Go to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
   - Select your environment
   - Go to Settings > Features
   - Enable "Managed Environment" if not already enabled
   - Wait for the environment to finish updating (check History tab)

4. **Register Azure Subscription for Power Platform**
   ```powershell
   # Run the subscription setup script
   .\powershell\enterprisePolicies\SetupSubscriptionForPowerPlatform.ps1
   ```

### 2. Update Configuration Variables

Edit the `azure-environment.ps1` script and update these variables at the top:

```powershell
# Update these values for your environment
$resourceGroupName = "YourResourceGroup"        # Your resource group name
$location = "eastus"                            # Primary region
$keyVaultName = "your-keyvault-name"            # Must be globally unique
$secretName = "yourSecretName"                  # Secret name in Key Vault
$secretValue = "yourSecretValue"                # Secret value
$userEmail = "admin@yourdomain.com"             # Your admin email
$powerPlatformAdminUserId = "user-object-id"    # Power Platform admin user object ID
$powerPlaftformEnvironmentId = "environment-id" # Your Power Platform environment ID
```

To get your Power Platform Environment ID:
- Go to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
- Select Environments > [Your Environment]
- Copy the Environment ID from the details section

To get your User Object ID:
```powershell
# Get current user's object ID
(Get-AzADUser -UserPrincipalName "admin@yourdomain.com").Id
```

### 3. Run the Main Setup Script

Execute the main deployment script:

```powershell
# Run from the repository root directory
.\azure-environment.ps1
```

The script will automatically:
1. ✅ Create resource group and Key Vault
2. ✅ Add secrets to Key Vault
3. ✅ Grant user access to Key Vault
4. ✅ Create dual-region VNet infrastructure
5. ✅ Delegate subnets to Power Platform
6. ✅ Create and configure enterprise policy
7. ✅ Apply VNet injection to Power Platform environment
8. ✅ Set up private endpoints for Key Vault
9. ✅ Configure private DNS zones and VNet peering
10. ✅ Apply Key Vault network restrictions

**Expected Duration**: 15-30 minutes (VNet injection may take 5-15 minutes to propagate)

### 4. Verify Deployment

Run the verification script to confirm everything is configured correctly:

```powershell
# Run the troubleshooting script
.\troubleshoot-vnet-integration.ps1
```

Expected successful output:
- ✅ Azure resources created
- ✅ VNet integration active
- ✅ DNS resolution working (resolving to private IP)
- ✅ Environment region retrieved

### 5. Architecture Overview

The deployment creates the following architecture:

**Network Architecture:**
- **Primary Region (East US)**:
  - VNet: 192.168.0.0/16
  - Power Platform Subnet: 192.168.1.0/24 (delegated)
  - Private Endpoint Subnet: 192.168.2.0/24
  - Key Vault Access Subnet: 192.168.3.0/24

- **Secondary Region (West US)**:
  - VNet: 192.169.0.0/16
  - Power Platform Subnet: 192.169.1.0/24 (delegated)
  - Key Vault Access Subnet: 192.169.3.0/24

**Security Configuration:**
- Key Vault with private endpoint (no public access)
- Private DNS zone for Key Vault resolution
- VNet peering between regions
- Network ACLs restricting access to delegated subnets

### 6. Key Vault Security Approaches

This solution implements the **Private Endpoint Method (Recommended)**:

**What's Included:**
- ✅ Private endpoint for Key Vault in primary region
- ✅ Private DNS zone with automatic DNS resolution
- ✅ VNet peering for cross-region access
- ✅ Network ACLs for additional security layer
- ✅ Disabled public network access

**Alternative: Service Endpoint Method** (not implemented, for reference):
- Uses service endpoints on delegated subnets
- Key Vault firewall allows specific subnet access
- Traffic stays on Azure backbone but not fully private
- No private DNS required

### 7. Test Connectivity

After deployment, test the connection from your Power Platform environment:

1. **Create a Power Automate Flow**:
   - Add HTTP action to call Azure Key Vault REST API
   - Use Managed Identity authentication
   - Verify secret retrieval works

2. **Test DNS Resolution**:
   ```powershell
   # Run DNS test from troubleshooting script
   Test-DnsResolution -EnvironmentId "your-env-id" -HostName "your-keyvault.vault.azure.net"
   ```
   Expected: Should resolve to private IP (192.168.2.x)

3. **Verify Network Connectivity**:
   ```powershell
   # First, get the Key Vault private IP address
   $privateEndpoint = Get-AzPrivateEndpoint -Name "kv-power-app-2025-private-endpoint" -ResourceGroupName "PPVNetUS-rs"
   $networkInterface = Get-AzNetworkInterface -ResourceId ($privateEndpoint.NetworkInterfaces[0].Id)
   $privateIpAddress = $networkInterface.IpConfigurations[0].PrivateIpAddress
   Write-Host "Key Vault Private IP: $privateIpAddress"
   
   # Test network connectivity using the private IP
   Test-NetworkConnectivity -EnvironmentId "your-env-id" -RemoteHost $privateIpAddress -RemotePort 443
   ```
   Expected: Connection should succeed

---

## Troubleshooting

### Common Issues and Solutions

**Issue: "Subnet information not found" error**
- **Cause**: VNet injection not applied or still processing
- **Solution**: 
  1. Check Power Platform Admin Center > Environments > History
  2. Wait 5-15 minutes for propagation
  3. Re-run `.\troubleshoot-vnet-integration.ps1`

**Issue: "SubnetMissingRequiredDelegation" error**
- **Cause**: Subnet not properly delegated or has conflicting service endpoints
- **Solution**:
  1. Remove existing service endpoints from Power Platform subnets
  2. Re-run `.\powershell\enterprisePolicies\SubnetInjection\SetupVnetForSubnetDelegation.ps1`

**Issue: Key Vault access denied**
- **Cause**: Network rules blocking access or permissions issue
- **Solution**:
  1. Verify VNet integration is active
  2. Check Key Vault network rules include correct subnets
  3. Verify user has proper Key Vault access policy

**Issue: DNS not resolving to private IP**
- **Cause**: Private DNS zone not linked or VNet link missing
- **Solution**:
  1. Verify private DNS zone exists
  2. Check VNet links are configured
  3. Ensure VNet peering is established

**Issue: PowerShell module errors**
- **Cause**: Missing or outdated modules
- **Solution**:
  ```powershell
  # Reinstall modules
  Install-Module -Name Az -Force -AllowClobber
  Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force
  Install-Module -Name Microsoft.PowerPlatform.EnterprisePolicies -Force
  ```

### Diagnostic Scripts

Use the provided diagnostic scripts:

1. **`troubleshoot-vnet-integration.ps1`**: Complete diagnostic check
2. **`verify-environment-details.ps1`**: Detailed environment verification with retry logic

### Getting Help

If issues persist:
1. Review error messages and correlation IDs
2. Check [Microsoft Troubleshooting Guide](https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network)
3. Open an issue in this repository with:
   - Error messages
   - Correlation IDs
   - Output from diagnostic scripts

---

## Scripts Overview

### Main Setup Script
- **`azure-environment.ps1`**: Complete infrastructure deployment and configuration

### Diagnostic Scripts
- **`troubleshoot-vnet-integration.ps1`**: Comprehensive VNet integration diagnostics
- **`verify-environment-details.ps1`**: Detailed environment verification with retry logic

### Custom Connector Simulation Scripts
- **`deploy-internal-api.ps1`**: Deploy a private Web API to simulate internal API scenarios
- **`test-internal-api.ps1`**: Test connectivity to the internal API from Power Platform

### Enterprise Policy Scripts (in `powershell/enterprisePolicies/`)
- **`InstallPowerAppsCmdlets.ps1`**: Install required PowerShell modules
- **`SetupSubscriptionForPowerPlatform.ps1`**: Register subscription for Power Platform
- **`SubnetInjection/SetupVnetForSubnetDelegation.ps1`**: Configure subnet delegation
- **`SubnetInjection/CreateSubnetInjectionEnterprisePolicy.ps1`**: Create enterprise policy
- **`SubnetInjection/NewSubnetInjection.ps1`**: Apply VNet injection to environment
- **`SubnetInjection/RevertSubnetInjection.ps1`**: Remove VNet injection from environment

---

## Custom Connector Simulation

This solution includes scripts to deploy and test a private internal API that simulates real-world custom connector scenarios where Power Platform needs to access internal APIs.

### What It Does
- Deploys an Azure App Service (Web API) with **public access disabled**
- Configures a **private endpoint** in your VNet with a private IP address
- Sets up **Private DNS** for name resolution within the VNet
- Creates sample API endpoints that are **only accessible through VNet integration**

### Deploy Internal API

Run the deployment script to create the private API:

```powershell
.\deploy-internal-api.ps1 -WebAppName "my-internal-api-demo"
```

**What gets deployed:**
- Azure App Service Plan (Basic B1 tier)
- Azure Web App with public access disabled
- Private Endpoint in your VNet (gets a private IP like 192.168.2.x)
- Private DNS Zone (privatelink.azurewebsites.net)
- Sample API with these endpoints:
  - `GET /api/health` - Health check
  - `GET /api/data` - Sample data  
  - `POST /api/echo` - Echo service

**Deployment takes ~3-5 minutes**. Wait an additional 5-10 minutes for private endpoint DNS propagation.

### Test Internal API Access

After deployment, verify Power Platform can access the API:

```powershell
.\test-internal-api.ps1 -WebAppName "my-internal-api-demo"
```

**The test checks:**
1. ✅ DNS resolution (should resolve to private IP)
2. ✅ Network connectivity (port 443)
3. 📋 Configuration summary

### Create Custom Connector in Power Platform

1. **In Power Apps or Power Automate:**
   - Go to **Data** → **Custom Connectors** → **New custom connector** → **Create from blank**

2. **General Tab:**
   - **Host**: `your-web-app-name.azurewebsites.net`
   - **Base URL**: `/`

3. **Security Tab:**
   - **Authentication type**: No authentication (for demo)
   - For production: Configure API Key, OAuth, etc.

4. **Definition Tab - Add Actions:**
   
   **Health Check Action:**
   - **Summary**: Check API Health
   - **Operation ID**: GetHealth
   - **Verb**: GET
   - **URL**: `/api/health`

   **Get Data Action:**
   - **Summary**: Get Internal Data
   - **Operation ID**: GetData
   - **Verb**: GET
   - **URL**: `/api/data`

   **Echo Action:**
   - **Summary**: Echo Test
   - **Operation ID**: PostEcho
   - **Verb**: POST
   - **URL**: `/api/echo`
   - **Body**: Add a parameter for JSON input

5. **Test Tab:**
   - Create a connection
   - Test each action
   - Should successfully connect through VNet! 🎉

### Verify It's Actually Private

To confirm the API is truly private and only accessible through VNet:

```powershell
# Try to access from public internet (should fail)
Invoke-WebRequest -Uri "https://your-web-app-name.azurewebsites.net/api/health"
# Expected: Connection timeout or 403 Forbidden

# But from Power Platform with VNet integration - should succeed!
# Test using the custom connector you created
```

### Use Cases

This simulation demonstrates common scenarios:
- **Internal line-of-business APIs**: Access on-premises or private Azure APIs
- **Database APIs**: Connect to APIs that access private databases
- **Secure microservices**: Integrate with backend services not exposed to internet
- **Compliance scenarios**: Keep data flows within private networks

---

## Clean Up Resources

### Option 1: Delete Resource Group (Complete Cleanup)
```powershell
# This removes ALL resources including VNets, Key Vault, DNS zones, etc.
Remove-AzResourceGroup -Name "PPVNetUS-rs" -Force
```

### Option 2: Remove VNet Integration Only
```powershell
# 1. Remove VNet injection from environment
.\powershell\enterprisePolicies\SubnetInjection\RevertSubnetInjection.ps1

# 2. Delete enterprise policy
$policyArmId = "/subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/Microsoft.PowerPlatform/enterprisePolicies/<policy-name>"
Remove-AzResource -ResourceId $policyArmId -Force

# 3. Optionally delete VNets and other resources as needed
```

**Important Notes:**
- Removing VNet injection can take 5-15 minutes to complete
- Enterprise policy cannot be deleted while associated with environments
- Key Vault has soft-delete enabled - use `-Force` to permanently delete

---

## Security Best Practices

1. **Credential Management**
   - Never commit secrets or credentials to source control
   - Use Azure Key Vault for all secrets
   - Rotate secrets regularly
   - Use Managed Identity when possible

2. **Network Security**
   - Always use private endpoints for production workloads
   - Implement Network Security Groups (NSGs) for additional protection
   - Use Azure Firewall or NAT Gateway for outbound internet access
   - Monitor network traffic with Azure Network Watcher

3. **Access Control**
   - Follow principle of least privilege
   - Use Azure RBAC for resource access
   - Enable MFA for all admin accounts
   - Regularly audit role assignments

4. **Monitoring & Compliance**
   - Enable Azure Monitor and diagnostic logs
   - Set up alerts for suspicious activities
   - Use Azure Policy for compliance enforcement
   - Regular security assessments with Microsoft Defender for Cloud

---

## References

### Official Documentation
- [Power Platform VNet Integration Overview](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [Set up VNet Integration](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure)
- [Troubleshooting Virtual Networks](https://learn.microsoft.com/en-us/troubleshoot/power-platform/administration/virtual-network)
- [Azure Key Vault Private Endpoints](https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service)
- [Azure Private DNS Zones](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)

### PowerShell Modules
- [Az PowerShell Module](https://learn.microsoft.com/en-us/powershell/azure/install-azure-powershell)
- [Power Apps Administration](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell)
- [Enterprise Policies GitHub Repo](https://github.com/microsoft/PowerPlatform-EnterprisePolicies)

### Additional Resources
- [Azure VNet Peering](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview)
- [Subnet Delegation](https://learn.microsoft.com/en-us/azure/virtual-network/subnet-delegation-overview)
- [Power Platform Managed Environments](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview)

---

## FAQ

**Q: Can I use this in production?**
A: Yes, but ensure you review and adjust sizing, security settings, and region selection for your specific requirements.

**Q: What are the costs?**
A: Costs vary based on:
- VNet resources (minimal)
- Private endpoints (~$7-10/month per endpoint)
- Key Vault transactions
- Power Platform licensing
- Data transfer between regions

**Q: Can I use different regions?**
A: Yes, but both VNets must be in regions that map to your Power Platform geography. See [supported regions](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions).

**Q: Do I need both VNets?**
A: Yes, for high availability. Power Platform environments can fail over between regions in the same geography.

**Q: Can I connect to on-premises resources?**
A: Yes, through Azure ExpressRoute or VPN Gateway connected to your delegated VNets.

**Q: What happens if I delete the enterprise policy?**
A: You must first remove VNet injection from all associated environments, or the delete will fail.

---

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

This project is provided under the MIT License. See LICENSE file for details.

---

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review [FAQ](#faq)
3. Open an issue in this repository
4. Contact Microsoft Support for Power Platform-specific issues

---

## Changelog

### Version 1.0.0 (2025-12-03)
- Initial release
- Complete VNet integration setup
- Private endpoint configuration
- Dual-region support
- Diagnostic and troubleshooting scripts

---

**Ready to get started? Follow the [Implementation Steps](#implementation-steps) above!**
