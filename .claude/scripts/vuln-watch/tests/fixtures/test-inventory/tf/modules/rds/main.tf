resource "aws_db_subnet_group" "main" {
  name = "main"
}

resource "aws_db_instance" "main" {
  engine         = "postgres"
  engine_version = "17"
}

# resource の外の engine_version は、版にならない
locals {
  engine_version = "16"
}
