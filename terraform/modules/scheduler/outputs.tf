output "db_start_schedule_group_name" {
  description = "Name of the schedule group that contains only the scheduled DB start"
  value       = aws_scheduler_schedule_group.db_start.name
}
