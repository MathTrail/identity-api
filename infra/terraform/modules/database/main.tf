# Database Abstraction Module
# mode = "k8s"     -> uses existing shared PostgreSQL in cluster
# mode = "managed" -> creates AWS RDS instance
# Both output identical: host, port, username, db_name
# Passwords always go to Vault, never in Terraform outputs

# --- Managed RDS (when mode = "managed") ---

resource "aws_db_subnet_group" "this" {
  count      = var.mode == "managed" ? 1 : 0
  name       = "${var.service_name}-db-subnet"
  subnet_ids = var.subnet_ids

  tags = {
    Name    = "${var.service_name}-db-subnet"
    Service = var.service_name
  }
}

resource "aws_db_instance" "this" {
  count = var.mode == "managed" ? 1 : 0

  identifier     = var.service_name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.service_name

  manage_master_user_password = true

  db_subnet_group_name = aws_db_subnet_group.this[0].name

  skip_final_snapshot = true

  tags = {
    Name    = var.service_name
    Service = var.service_name
  }
}
