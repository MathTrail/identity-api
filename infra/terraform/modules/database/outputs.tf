output "db_host" {
  description = "Database host address"
  value       = var.mode == "managed" ? aws_db_instance.this[0].address : "postgres-postgresql.${var.namespace}.svc.cluster.local"
}

output "db_port" {
  description = "Database port"
  value       = var.mode == "managed" ? aws_db_instance.this[0].port : 5432
}

output "db_name" {
  description = "Database name"
  value       = var.db_name
}

output "db_username" {
  description = "Database username"
  value       = var.mode == "managed" ? aws_db_instance.this[0].username : var.service_name
}
