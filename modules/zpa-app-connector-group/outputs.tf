output "id" {
  description = "ID of the App Connector Group (used by zpa_server_group.app_connector_groups)."
  value       = zpa_app_connector_group.this.id
}

output "name" {
  description = "Name of the App Connector Group."
  value       = zpa_app_connector_group.this.name
}
