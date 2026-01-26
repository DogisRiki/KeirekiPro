# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-task-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_base" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "ecs_secrets" {
  name        = "${var.project_name}-ecs-secrets-policy"
  description = "Policy for ECS task execution role to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetSecrets"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:ap-northeast-1:${var.aws_account_id}:secret:${var.project_name}/*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-secrets-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_secrets.arn
}

# ECS Task Role
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ecs-task-role"
  }
}

resource "aws_iam_policy" "app_secrets" {
  name        = "${var.project_name}-app-secrets-policy"
  description = "Policy for application to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetSecrets"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:ap-northeast-1:${var.aws_account_id}:secret:${var.project_name}/*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-app-secrets-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_secrets" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.app_secrets.arn
}

resource "aws_iam_policy" "s3_policy" {
  name        = "${var.project_name}-s3-policy"
  description = "Policy for S3 access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${var.s3_storage_bucket_arn}/*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-s3-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_s3" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_policy" "ses_policy" {
  name        = "${var.project_name}-ses-policy"
  description = "Policy for SES email sending"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SESSendEmail"
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = "info@keirekipro.click"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ses-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_ses" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = aws_iam_policy.ses_policy.arn
}
