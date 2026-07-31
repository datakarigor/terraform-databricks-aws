variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    "Project" = "Databricks AWS Terraform"
  }
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "dbx-learn"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "databricks_client_id" {
  description = "Databricks client ID"
  type        = string
}

variable "databricks_client_secret" {
  description = "Databricks client secret"
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account ID"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.4.0.0/16"
}