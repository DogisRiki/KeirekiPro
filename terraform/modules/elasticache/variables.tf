variable "project_name" {
  description = "Project name"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for Redis"
  type        = string
}

variable "auth_token" {
  description = "Redis AUTH token"
  type        = string
  sensitive   = true
}
