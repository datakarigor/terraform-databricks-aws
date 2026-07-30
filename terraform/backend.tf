terraform {
  backend "s3" {
    bucket       = "terraform-databricks-aws"
    key          = "terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}