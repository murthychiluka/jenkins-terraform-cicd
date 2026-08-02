terraform {
  backend "s3" {
  bucket = "murthy-terraform"
  key    = "Day03/terraform.tfstate"
  region = "us-east-1"
  }
}
