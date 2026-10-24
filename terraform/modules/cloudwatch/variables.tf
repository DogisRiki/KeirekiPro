variable "project_name" {
  description = "Project name"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix"
  type        = string
}

variable "rds_instance_identifier" {
  description = "RDS instance identifier"
  type        = string
}

variable "redis_cluster_id" {
  description = "ElastiCache Serverless cache name (clusterId dimension)"
  type        = string
}

variable "alert_email_address" {
  description = "Email address for alert notifications"
  type        = string
  sensitive   = true
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "db_start_schedule_group_name" {
  description = "Name of the EventBridge Scheduler schedule group that contains only the scheduled DB start"
  type        = string
}
