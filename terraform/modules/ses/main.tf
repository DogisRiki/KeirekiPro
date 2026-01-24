# SES Configuration Set
resource "aws_ses_configuration_set" "main" {
  name = "${var.project_name}-config-set"

  reputation_metrics_enabled = false
  sending_enabled            = true
}
