output "storage_account_id" {
  description = "Sample storage account."
  value       = azurerm_storage_account.app.id
}

output "key_vault_id" {
  description = "Sample Key Vault."
  value       = azurerm_key_vault.app.id
}

output "private_endpoint_ips" {
  description = "Private IPs of the two private endpoints."
  value = {
    blob  = azurerm_private_endpoint.blob.private_service_connection[0].private_ip_address
    vault = azurerm_private_endpoint.vault.private_service_connection[0].private_ip_address
  }
}
