# Network Security Group (NSG) Best Practices
## For Power Platform VNet Integration

This guide explains NSG configuration best practices for Power Platform VNet integration scenarios.

---

## Table of Contents
1. [Do You Need NSGs?](#do-you-need-nsgs)
2. [Which Subnets Need NSGs?](#which-subnets-need-nsgs)
3. [Recommended NSG Rules](#recommended-nsg-rules)
4. [Security Considerations](#security-considerations)
5. [Common Scenarios](#common-scenarios)
6. [Troubleshooting](#troubleshooting)

---

## Do You Need NSGs?

### Short Answer: **Optional for Basic Functionality**

Power Platform VNet integration works **without NSGs** because:
- Private endpoints handle network isolation
- VNet integration uses subnet delegation (no NSG required)
- Default Azure security applies automatically

### When to Use NSGs:

✅ **Use NSGs if you need:**
- **Defense-in-depth security** (multiple security layers)
- **Explicit deny rules** for compliance
- **Granular traffic control** (specific ports/protocols)
- **Audit trail** of network security policies
- **Compliance requirements** (PCI-DSS, HIPAA, etc.)

❌ **Skip NSGs if:**
- You trust Azure default security
- Private endpoints are sufficient for your security model
- You want to simplify architecture
- No compliance requirements mandate NSGs

---

## Which Subnets Need NSGs?

### Priority Matrix

| Subnet Type | NSG Priority | Reason |
|-------------|--------------|--------|
| **Power Platform Delegated** | Optional | Already isolated by delegation; NSG adds control |
| **Private Endpoint** | Optional | Private Link bypasses NSG rules anyway |
| **Key Vault Access** | Optional | Service endpoints don't require NSGs |
| **Default/Compute** | Recommended | General-purpose subnets benefit from explicit rules |

### Detailed Breakdown

#### 1. Power Platform Delegated Subnets
**Subnet Names:** `PPENVIRONMENT`, `SUBNET-POWER-PLATFORM-*`

**NSG Needed?** ⚠️ Optional (Defense-in-depth)

**Why:**
- Subnet is already delegated to `Microsoft.PowerPlatform/enterprisePolicies`
- Traffic is controlled at the delegation level
- NSG adds an extra security layer

**Recommended Rules:**
```powershell
# Outbound
- Allow HTTPS (443) to Internet          # Power Platform services
- Allow SQL (1433) to Sql service tag    # Database connectors
- Allow HTTPS (443) to AzureKeyVault     # Key Vault access
- Allow all to VirtualNetwork            # Internal communication

# Inbound
- Allow all from VirtualNetwork          # Inter-subnet communication
- Deny all from Internet (explicit)      # Extra security
```

#### 2. Private Endpoint Subnets
**Subnet Names:** `SUBNET-PRIV-ENDPOINT-*`, `subnet-private-endpoints-*`

**NSG Needed?** ❌ Not Required (Low Value)

**Why:**
- Private endpoints use **Private Link** technology
- Traffic goes through Azure backbone, not VNet routing
- **NSG rules are bypassed** for Private Link traffic
- Microsoft documentation: "NSGs on private endpoint subnets are not enforced"

**If You Still Want NSG (for logging/compliance):**
```powershell
# Inbound
- Allow HTTPS (443) from VirtualNetwork  # Allow VNet access

# Outbound
- Allow all to VirtualNetwork            # Return traffic
```

⚠️ **Important:** These rules are mostly symbolic since Private Link bypasses them!

#### 3. Key Vault Access Subnets
**Subnet Names:** `SUBNET-KEYVAULT-*`

**NSG Needed?** ⚠️ Optional (Adds Control)

**Why:**
- Uses **service endpoints** (not private endpoints)
- NSG rules **do apply** to service endpoint traffic
- Can restrict which services access Key Vault

**Recommended Rules:**
```powershell
# Outbound
- Allow HTTPS (443) to AzureKeyVault     # Key Vault service endpoint
- Allow HTTPS (443) to Internet          # For other Azure services
- Deny all other outbound (optional)     # Strict control

# Inbound
- Allow all from VirtualNetwork          # Internal traffic
- Deny all from Internet                 # Block public access
```

#### 4. Default/General Subnets
**Subnet Names:** `DEFAULT`, `subnet-general`, etc.

**NSG Needed?** ✅ Recommended

**Why:**
- No special Azure service protection
- Good practice for any compute resources
- Prevents accidental exposure

**Recommended Rules:**
```powershell
# Inbound
- Allow SSH (22) or RDP (3389) from management subnet (if VMs)
- Allow HTTPS (443) from load balancer (if web apps)
- Allow all from VirtualNetwork
- Deny all from Internet

# Outbound
- Allow all to VirtualNetwork
- Allow HTTPS (443) to Internet
- (Optional) Allow specific ports for required services
```

---

## Recommended NSG Rules

### Template: Power Platform Delegated Subnet

```powershell
# Rule Priority Guide: 100-999 = Allow rules, 1000-4095 = Deny rules

# Inbound Rules
Priority 100: Allow-VNet-Inbound
  - Source: VirtualNetwork
  - Destination: VirtualNetwork
  - Ports: Any
  - Protocol: Any
  - Action: Allow

Priority 4000: Deny-Internet-Inbound
  - Source: Internet
  - Destination: Any
  - Ports: Any
  - Protocol: Any
  - Action: Deny

# Outbound Rules
Priority 100: Allow-HTTPS-Outbound
  - Source: VirtualNetwork
  - Destination: Internet
  - Ports: 443
  - Protocol: TCP
  - Action: Allow

Priority 110: Allow-SQL-Outbound
  - Source: VirtualNetwork
  - Destination: Sql (Service Tag)
  - Ports: 1433
  - Protocol: TCP
  - Action: Allow

Priority 120: Allow-KeyVault-Outbound
  - Source: VirtualNetwork
  - Destination: AzureKeyVault (Service Tag)
  - Ports: 443
  - Protocol: TCP
  - Action: Allow
```

### Template: Private Endpoint Subnet

```powershell
# Minimal NSG (mostly for compliance/logging)

# Inbound Rules
Priority 100: Allow-HTTPS-VNet-Inbound
  - Source: VirtualNetwork
  - Destination: VirtualNetwork
  - Ports: 443
  - Protocol: TCP
  - Action: Allow

# Outbound Rules
Priority 100: Allow-VNet-Outbound
  - Source: VirtualNetwork
  - Destination: VirtualNetwork
  - Ports: Any
  - Protocol: Any
  - Action: Allow
```

---

## Security Considerations

### Defense-in-Depth Strategy

NSGs are one layer in a multi-layered security approach:

```
Layer 1: Azure AD / Identity                    (Authentication)
Layer 2: Private Endpoints / VNet Integration   (Network Isolation)
Layer 3: NSGs                                   (Traffic Filtering) ← You are here
Layer 4: Azure Firewall / NAT Gateway           (Centralized Control)
Layer 5: Application Security                   (Input Validation)
```

### NSG Limitations

**What NSGs CAN'T Do:**
- ❌ Inspect packet contents (not a firewall)
- ❌ Block Private Link traffic (bypasses NSGs)
- ❌ Provide application-layer filtering
- ❌ Decrypt or inspect TLS/SSL traffic
- ❌ Replace Azure Firewall for advanced scenarios

**What NSGs CAN Do:**
- ✅ Allow/deny based on IP, port, protocol
- ✅ Use service tags for Azure services
- ✅ Provide audit logs (with NSG flow logs)
- ✅ Create explicit security boundaries
- ✅ Simplify compliance documentation

### Cost Considerations

**NSG Costs:**
- NSGs themselves: **FREE** ✅
- NSG Flow Logs: **Charged** (storage costs for logs)
- Traffic processing: **FREE** (no per-GB charge)

**Recommendation:** Use NSGs freely, but be mindful of flow log storage costs.

---

## Common Scenarios

### Scenario 1: Minimal Security (Simplest)
**Goal:** Basic security, simplest architecture

**NSG Configuration:**
- Power Platform subnets: **No NSG**
- Private endpoint subnets: **No NSG**
- Key Vault subnets: **No NSG**

**Security Provided:**
- Private endpoints handle isolation
- Azure default security applies
- Simplest to manage

**Use When:**
- Development/test environments
- Low security requirements
- Want simplest architecture

---

### Scenario 2: Moderate Security (Recommended)
**Goal:** Balance security and complexity

**NSG Configuration:**
- Power Platform subnets: **NSG with outbound rules**
  - Allow HTTPS, SQL, Key Vault
  - Deny internet inbound explicitly
- Private endpoint subnets: **No NSG** (low value)
- Key Vault subnets: **NSG with service endpoint rules**
  - Allow Key Vault service endpoint
  - Deny internet inbound

**Security Provided:**
- Explicit control over outbound traffic
- Defense-in-depth compliance
- Clear security boundaries

**Use When:**
- Production environments
- Moderate compliance needs
- Want clear security policies

---

### Scenario 3: Maximum Security (Strictest)
**Goal:** Highest security, full compliance

**NSG Configuration:**
- **All subnets have NSGs** with:
  - Explicit allow rules only
  - Default deny for everything else
  - NSG flow logs enabled
  - Alert rules for unusual traffic
- **Azure Firewall** for centralized control
- **Private DNS** for all Azure services

**Security Provided:**
- Zero trust network model
- Full audit trail
- Granular traffic control
- Meets strictest compliance (PCI-DSS, HIPAA)

**Use When:**
- Financial services / Healthcare
- Government / Defense
- High compliance requirements
- Security-first culture

---

## Troubleshooting

### Issue: Power Platform can't connect after adding NSG

**Symptoms:**
- Custom connectors fail
- "Connection timeout" errors
- Power Automate flows fail

**Solution:**
1. Check NSG has **Allow HTTPS (443) outbound** to Internet/Service Tags
2. Ensure **no overly restrictive deny rules** blocking Power Platform services
3. Verify **VNet inbound is allowed** for inter-subnet communication

```powershell
# Quick fix: Add allow rule for Power Platform services
Add-AzNetworkSecurityRuleConfig `
  -NetworkSecurityGroup $nsg `
  -Name "Allow-PowerPlatform-Outbound" `
  -Priority 100 `
  -Direction Outbound `
  -Access Allow `
  -Protocol Tcp `
  -SourcePortRange "*" `
  -DestinationPortRange "443" `
  -SourceAddressPrefix "VirtualNetwork" `
  -DestinationAddressPrefix "Internet"
```

### Issue: Private endpoint not working with NSG

**Symptoms:**
- Can't connect to Key Vault private endpoint
- DNS resolves but connection fails

**Solution:**
1. **Remember:** Private endpoints **bypass NSG rules**
2. Problem is likely **DNS or private endpoint config**, not NSG
3. Check private DNS zone configuration
4. Verify private endpoint is in "Succeeded" state

```powershell
# Verify private endpoint status
Get-AzPrivateEndpoint -Name "kv-power-app-2025-private-endpoint" -ResourceGroupName "PPVNetUS-rs" | Select-Object ProvisioningState, ManualPrivateLinkServiceConnections
```

### Issue: Too many NSGs created automatically

**Symptoms:**
- Multiple NSGs in resource group
- All have similar names
- Most have no custom rules

**Solution:**
Use the cleanup script:

```powershell
# Preview cleanup
.\cleanup-nsgs.ps1 -WhatIf

# Remove unassociated NSGs only (safe)
.\cleanup-nsgs.ps1 -CleanupMode RemoveUnassociated

# Or use interactive mode
.\cleanup-nsgs.ps1 -CleanupMode Interactive
```

---

## Quick Reference

### NSG Decision Tree

```
Do you have compliance requirements?
├─ YES → Use NSGs on all subnets (Scenario 3)
└─ NO → Continue...
    │
    Is this production?
    ├─ YES → Use NSGs on Power Platform & Key Vault subnets (Scenario 2)
    └─ NO → Skip NSGs or use minimal (Scenario 1)
```

### Essential Commands

```powershell
# List all NSGs and associations
Get-AzNetworkSecurityGroup -ResourceGroupName "PPVNetUS-rs" | Select-Object Name, @{N='Subnets';E={$_.Subnets.Count}}

# Add custom security rules
.\configure-nsg-rules.ps1 -WhatIf  # Preview first
.\configure-nsg-rules.ps1          # Apply changes

# Clean up NSGs
.\cleanup-nsgs.ps1 -CleanupMode RemoveUnassociated

# View NSG rules for specific NSG
$nsg = Get-AzNetworkSecurityGroup -Name "YourNSGName" -ResourceGroupName "PPVNetUS-rs"
$nsg.SecurityRules | Format-Table Name, Priority, Direction, Access, Protocol, SourceAddressPrefix, DestinationPortRange
```

---

## Summary

**Key Takeaways:**
1. NSGs are **optional** for Power Platform VNet integration
2. **Private endpoints bypass NSG rules** - don't expect NSGs to control Private Link traffic
3. Use NSGs for **defense-in-depth** and **compliance**, not as primary security
4. Start simple (no NSGs) → add as needed for your security requirements
5. Use the provided scripts to configure or clean up NSGs

**Recommended Approach:**
- **Dev/Test:** No NSGs (simplest)
- **Production:** NSGs on Power Platform and Key Vault subnets
- **High Security:** NSGs on all subnets + Azure Firewall

---

## Additional Resources

- [Azure NSG Documentation](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview)
- [Private Link and NSGs](https://learn.microsoft.com/azure/private-link/disable-private-endpoint-network-policy)
- [Power Platform VNet Integration](https://learn.microsoft.com/power-platform/admin/vnet-support-overview)
- [Service Tags](https://learn.microsoft.com/azure/virtual-network/service-tags-overview)

---

**Scripts in This Repository:**
- `configure-nsg-rules.ps1` - Add recommended security rules to NSGs
- `cleanup-nsgs.ps1` - Remove unnecessary NSGs
- `troubleshoot-vnet-integration.ps1` - Diagnose VNet integration issues
