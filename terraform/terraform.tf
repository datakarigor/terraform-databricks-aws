terraform {
    backend "s3" {
        bucket = "terraform-databricks-aws"
        key    = "terraform.tfstate"
        region = "eu-north-1"
    }
    
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.0"
        }
    }
}