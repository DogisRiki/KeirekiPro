variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN"
  type        = string
}

variable "alb_logs_bucket_name" {
  description = "S3 bucket name for ALB logs"
  type        = string
}

variable "origin_verify_header_value" {
  description = "X-Origin-Verify header value"
  type        = string
  sensitive   = true
}

variable "api_certificate_arn" {
  description = "ACM certificate ARN for API subdomain"
  type        = string
}
