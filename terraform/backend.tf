terraform {
  backend "s3" {
    bucket         = "keirekipro-terraform-state"
    key            = "terraform.tfstate"
    region         = "ap-northeast-1"
    encrypt        = true
    dynamodb_table = "keirekipro-terraform-lock"
  }
}
