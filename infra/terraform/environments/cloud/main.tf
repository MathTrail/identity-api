terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Identity databases (kratos, hydra, keto) need managed RDS in cloud.
# Each Ory component gets its own database on the same RDS instance.

module "database" {
  source = "../../modules/database"

  mode           = "managed"
  service_name   = "mathtrail-identity"
  db_name        = "kratos"
  instance_class = var.db_instance_class
  vpc_id         = var.vpc_id
  subnet_ids     = var.subnet_ids
}

output "db_host" {
  value = module.database.db_host
}

output "db_port" {
  value = module.database.db_port
}
