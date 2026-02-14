variable "mode" {
  description = "Database deployment mode"
  type        = string
  validation {
    condition     = contains(["k8s", "managed"], var.mode)
    error_message = "Must be 'k8s' or 'managed'."
  }
}

variable "service_name" {
  description = "Service name (used for naming resources)"
  type        = string
}

variable "db_name" {
  description = "Database name to create"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "mathtrail"
}

# AWS-specific (only when mode = "managed")
variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "vpc_id" {
  description = "VPC ID for RDS"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS"
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}
