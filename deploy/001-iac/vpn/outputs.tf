/*
 * VPN Gateway Outputs
 */

output "vpn_gateway" {
  description = "VPN Gateway resource details"
  value       = module.vpn.vpn_gateway
}

output "vpn_gateway_public_ip" {
  description = "Public IP address of the VPN Gateway"
  value       = module.vpn.vpn_gateway_public_ip
}

output "gateway_subnet" {
  description = "Gateway subnet details"
  value       = module.vpn.gateway_subnet
}

/*
 * DNS Private Resolver Outputs
 */

output "dns_resolver" {
  description = "The Azure Private Resolver resource"
  value       = module.vpn.private_resolver
}

output "resolver_subnet" {
  description = "The subnet created for the Private Resolver"
  value       = module.vpn.resolver_subnet
}

output "dns_server_ip" {
  description = "The IP address to use as DNS server for VPN clients"
  value       = module.vpn.dns_server_ip
}

/*
 * Client Hosts File Helper
 */

output "aks_hosts_file_command" {
  description = "Command to add AKS private endpoint to /etc/hosts for kubectl access over VPN"
  value       = module.vpn.aks_hosts_file_command
}

/*
 * P2S Connection Info
 */

output "p2s_connection_info" {
  description = "Point-to-Site VPN connection information"
  value       = module.vpn.p2s_connection_info
}

/*
 * S2S Connection Outputs
 */

output "site_connections" {
  description = "Site-to-Site VPN connection details"
  value       = module.vpn.site_connections
}

output "local_network_gateways" {
  description = "Local network gateway details for each site"
  value       = module.vpn.local_network_gateways
}
