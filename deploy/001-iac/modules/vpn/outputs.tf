/**
 * # VPN Module Outputs
 *
 * Typed object outputs for consumption by other modules.
 */

/*
 * VPN Gateway Outputs
 */

output "vpn_gateway" {
  description = "VPN Gateway resource details"
  value = {
    id         = azurerm_virtual_network_gateway.main.id
    name       = azurerm_virtual_network_gateway.main.name
    sku        = azurerm_virtual_network_gateway.main.sku
    generation = azurerm_virtual_network_gateway.main.generation
  }
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN Gateway"
  value = {
    id         = azurerm_public_ip.vpn_gateway.id
    ip_address = azurerm_public_ip.vpn_gateway.ip_address
  }
}

output "gateway_subnet" {
  description = "Gateway subnet details"
  value = {
    id             = azurerm_subnet.gateway.id
    name           = azurerm_subnet.gateway.name
    address_prefix = azurerm_subnet.gateway.address_prefixes[0]
  }
}

/*
 * DNS Private Resolver Outputs
 */

output "private_resolver" {
  description = "The Azure Private Resolver resource"
  value = var.resolver_subnet_address_prefix != null ? {
    id   = azurerm_private_dns_resolver.main[0].id
    name = azurerm_private_dns_resolver.main[0].name
  } : null
}

output "resolver_subnet" {
  description = "The subnet created for the Private Resolver"
  value = var.resolver_subnet_address_prefix != null ? {
    id               = azurerm_subnet.resolver[0].id
    name             = azurerm_subnet.resolver[0].name
    address_prefixes = azurerm_subnet.resolver[0].address_prefixes
  } : null
}

output "dns_server_ip" {
  description = "The IP address to use as DNS server for VPN clients"
  value       = var.resolver_subnet_address_prefix != null ? azurerm_private_dns_resolver_inbound_endpoint.main[0].ip_configurations[0].private_ip_address : null
}

/*
 * Client Hosts File Helper
 */

output "aks_hosts_file_command" {
  description = "Command to add AKS private endpoint to /etc/hosts for kubectl access over VPN"
  value = var.resolver_subnet_address_prefix != null ? join(" && ", [
    "FQDN=$(az aks show -g <RG_NAME> -n <AKS_NAME> --query privateFqdn -o tsv)",
    "IP=$(dig @${azurerm_private_dns_resolver_inbound_endpoint.main[0].ip_configurations[0].private_ip_address} $FQDN +short)",
    "echo \"$IP $FQDN\" | sudo tee -a /etc/hosts"
  ]) : null
}

/*
 * P2S Connection Info
 */

output "p2s_connection_info" {
  description = "Point-to-Site VPN connection information"
  value = {
    client_address_pool = var.vpn_gateway_config.client_address_pool
    protocols           = ["OpenVPN", "IkeV2"]
    gateway_public_ip   = azurerm_public_ip.vpn_gateway.ip_address
    dns_server          = var.resolver_subnet_address_prefix != null ? azurerm_private_dns_resolver_inbound_endpoint.main[0].ip_configurations[0].private_ip_address : null
  }
}

/*
 * S2S Connection Outputs
 */

output "site_connections" {
  description = "Site-to-Site VPN connection details"
  value = try({
    for name, conn in azurerm_virtual_network_gateway_connection.sites : name => {
      id   = conn.id
      name = conn.name
    }
  }, {})
}

output "local_network_gateways" {
  description = "Local network gateway details for each site"
  value = try({
    for name, lgw in azurerm_local_network_gateway.sites : name => {
      id            = lgw.id
      name          = lgw.name
      address_space = lgw.address_space
    }
  }, {})
}
