# VPN Gateway

Point-to-Site and Site-to-Site VPN connectivity for secure remote access to private endpoints.

## 📋 Prerequisites

- Platform infrastructure deployed (`cd ../001-iac && terraform apply`)
- Terraform 1.5+ installed
- Core variables matching parent deployment (`environment`, `resource_prefix`, `location`)

## 🚀 Quick Start

```bash
cd deploy/001-iac/vpn

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit: environment, resource_prefix, location (must match 001-iac)

terraform init && terraform apply
```

Deployment takes 20-30 minutes for the VPN Gateway.

## ⚙️ Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `gateway_subnet_address_prefix` | GatewaySubnet CIDR (min /27) | `10.0.3.0/27` |
| `vpn_gateway_config.sku` | Gateway SKU | `VpnGw1` |
| `vpn_gateway_config.client_address_pool` | P2S client IP range | `["192.168.200.0/24"]` |
| `aad_auth_config.enabled` | Enable Azure AD auth | `true` |

## 🔐 Authentication Options

### Azure AD (Recommended)

Enabled by default. Users authenticate with their Azure AD credentials via the Azure VPN Client.

```hcl
aad_auth_config = {
  enabled = true
}
```

### Certificate

For environments without Azure AD integration:

```hcl
aad_auth_config = {
  enabled = false
}
root_certificate_public_data = "MIIC5jCCAc6g..." # Base64-encoded cert
```

## 💻 VPN Client Setup

1. Download the VPN client configuration from Azure Portal
2. Install Azure VPN Client (Windows/macOS) or OpenVPN
3. Import the downloaded profile
4. Connect using Azure AD credentials or certificate

## 🏢 Site-to-Site VPN

Connect on-premises networks:

```hcl
vpn_site_connections = [{
  name                 = "on-prem-datacenter"
  address_spaces       = ["10.100.0.0/16"]
  gateway_ip_address   = "203.0.113.10"
  shared_key_reference = "datacenter-key"
}]

vpn_site_shared_keys = {
  "datacenter-key" = "your-preshared-key"
}
```

## 🔗 Related

- [Parent README](../README.md) - Main infrastructure documentation
- [dns/README.md](../dns/README.md) - Private DNS for OSMO UI (requires VPN)
