resource "aws_s3_bucket" "logs" {
  bucket = "logs"
}

resource "aws_security_group" "app" {
  name = "app"
}
