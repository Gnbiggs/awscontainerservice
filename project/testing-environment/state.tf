terraform {
  backend "s3" {
    bucket = "terraform-state-file"
    key    = "testing-environment/terraform.tfstate"
    region = "us-west-2"
    assume_role = {
      role_arn = "arn:aws:iam::103565356570:role/terraform"
    }
  }
}