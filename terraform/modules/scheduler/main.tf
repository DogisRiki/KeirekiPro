# IAM Role for EventBridge Scheduler
resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-scheduler-role"
  }
}

resource "aws_iam_policy" "scheduler" {
  name        = "${var.project_name}-scheduler-policy"
  description = "Policy for EventBridge Scheduler to manage ECS and RDS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECSAccess"
        Effect   = "Allow"
        Action   = "ecs:UpdateService"
        Resource = "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:service/${var.ecs_cluster_name}/${var.ecs_service_name}"
      },
      {
        Sid    = "RDSAccess"
        Effect = "Allow"
        Action = [
          "rds:StartDBInstance",
          "rds:StopDBInstance"
        ]
        Resource = "arn:aws:rds:${var.aws_region}:${var.aws_account_id}:db:${var.rds_instance_identifier}"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-scheduler-policy"
  }
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler.arn
}

# ============================================================
# 平日朝 7:50 (JST) - RDS起動 + ECS起動
# ============================================================

resource "aws_scheduler_schedule" "rds_start" {
  name        = "${var.project_name}-rds-start"
  description = "Start RDS on weekday mornings"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(50 22 ? * SUN-THU *)"
  schedule_expression_timezone = "UTC"
  # UTC 22:50 = JST 07:50 (翌日), SUN-THU = 月〜金のJST朝

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      DbInstanceIdentifier = var.rds_instance_identifier
    })

    retry_policy {
      maximum_retry_attempts = 2
    }
  }

  state = "ENABLED"
}

resource "aws_scheduler_schedule" "ecs_start" {
  name        = "${var.project_name}-ecs-start"
  description = "Start ECS service on weekday mornings"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 23 ? * SUN-THU *)"
  schedule_expression_timezone = "UTC"
  # UTC 23:00 = JST 08:00 (翌日)

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      Cluster      = var.ecs_cluster_name
      Service      = var.ecs_service_name
      DesiredCount = 1
    })

    retry_policy {
      maximum_retry_attempts = 2
    }
  }

  state = "ENABLED"
}

# ============================================================
# 平日夜 20:00 (JST) - ECS停止 + RDS停止
# ============================================================

resource "aws_scheduler_schedule" "ecs_stop" {
  name        = "${var.project_name}-ecs-stop"
  description = "Stop ECS service on weekday evenings"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 11 ? * MON-FRI *)"
  schedule_expression_timezone = "UTC"
  # UTC 11:00 = JST 20:00

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      Cluster      = var.ecs_cluster_name
      Service      = var.ecs_service_name
      DesiredCount = 0
    })

    retry_policy {
      maximum_retry_attempts = 2
    }
  }

  state = "ENABLED"
}

resource "aws_scheduler_schedule" "rds_stop" {
  name        = "${var.project_name}-rds-stop"
  description = "Stop RDS on weekday evenings"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(5 11 ? * MON-FRI *)"
  schedule_expression_timezone = "UTC"
  # UTC 11:05 = JST 20:05 (ECS停止の5分後)

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      DbInstanceIdentifier = var.rds_instance_identifier
    })

    retry_policy {
      maximum_retry_attempts = 2
    }
  }

  state = "ENABLED"
}
