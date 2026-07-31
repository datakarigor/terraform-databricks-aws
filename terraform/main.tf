locals {
  prefix = "${var.prefix}-${var.environment}"
}

################# IAM Role and Policy for Databricks Cross-Account Access #################

# Fetch the AWS assume role policy for Databricks cross-account access
data "databricks_aws_assume_role_policy" "this" {
  provider    = databricks.mws
  external_id = var.databricks_account_id
}

# Create an IAM role for Databricks cross-account access
resource "aws_iam_role" "databricks_cross_account" {
  name               = "${local.prefix}-databricks-cross-account-role"
  assume_role_policy = data.databricks_aws_assume_role_policy.this.json
  tags               = var.tags
}

# Create an IAM policy for Databricks cross-account access
data "databricks_aws_crossaccount_policy" "this" {
  provider    = databricks.mws
  policy_type = "customer"
}

# Attach the IAM policy to the IAM role
resource "aws_iam_role_policy" "this" {
  name   = "${local.prefix}-databricks-cross-account-policy"
  role   = aws_iam_role.databricks_cross_account.id
  policy = data.databricks_aws_crossaccount_policy.this.json
}

# Allow IAM role/policy to propagate before Databricks validates it
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on      = [aws_iam_role_policy.this, aws_iam_role.databricks_cross_account]
  create_duration = "30s"
}

# Create Databricks MWS credentials for the IAM role
resource "databricks_mws_credentials" "this" {
  provider         = databricks.mws
  role_arn         = aws_iam_role.databricks_cross_account.arn
  credentials_name = "${local.prefix}-databricks-cross-account-credentials"
  depends_on       = [time_sleep.wait_for_iam_propagation]
}


################# vpc and networking configuration for Databricks workspace #################
data "aws_availability_zones" "available" {}

# Create a VPC module for the Databricks workspace
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name = "${local.prefix}-vpc"
  cidr = var.cidr_block
  azs  = data.aws_availability_zones.available.names
  tags = var.tags

  enable_dns_hostnames = true
  enable_nat_gateway   = true
  single_nat_gateway   = true
  create_igw           = true

  public_subnets  = [cidrsubnet(var.cidr_block, 3, 0)]
  private_subnets = [cidrsubnet(var.cidr_block, 3, 1), cidrsubnet(var.cidr_block, 3, 2)]

  manage_default_security_group = true
  default_security_group_name   = "${local.prefix}-default-sg"

  default_security_group_egress = [{
    cidr_blocks = "0.0.0.0/0"
  }]

  default_security_group_ingress = [{
    description = "Allow all internal TCP and UDP"
    self        = true
  }]
}

# Create VPC endpoints for S3, STS, and Kinesis Streams
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "3.2.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc.default_security_group_id]

  endpoints = {
    s3 = {
      service      = "s3"
      service_type = "Gateway"
      route_table_ids = flatten([module.vpc.public_route_table_ids,
      module.vpc.private_route_table_ids])
      tags = var.tags
    },
    sts = {
      service     = "sts"
      private_dns = true
      subnet_ids  = module.vpc.private_subnets
      tags        = var.tags
    },
    kinesis-streams = {
      service     = "kinesis-streams"
      private_dns = true
      subnet_ids  = module.vpc.private_subnets
      tags        = var.tags
    },
  }
  tags = var.tags
}

# Create a Databricks MWS network configuration for the VPC
resource "databricks_mws_networks" "this" {
  provider           = databricks.mws
  account_id         = var.databricks_account_id
  network_name       = "${local.prefix}-databricks-network"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.vpc.default_security_group_id]
}



################# Databricks Workspace and Storage Configuration #################
# Root S3 bucket for DBFS inside Databricks workspace. This bucket is used to store the root of the DBFS filesystem.
resource "aws_s3_bucket" "root_storage_bucket" {
  bucket        = "${local.prefix}-dbfs-root-bucket"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root_storage_bucket" {
  bucket = aws_s3_bucket.root_storage_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "root_storage_bucket" {
  bucket = aws_s3_bucket.root_storage_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.root_storage_bucket]
}

# Create a Databricks storage configuration for the S3 bucket
resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks.mws
  account_id                 = var.databricks_account_id
  bucket_name                = aws_s3_bucket.root_storage_bucket.bucket
  storage_configuration_name = "${local.prefix}-databricks-storage-configuration"
}

data "databricks_aws_bucket_policy" "this" {
  bucket = aws_s3_bucket.root_storage_bucket.bucket
}

resource "aws_s3_bucket_policy" "root_storage_bucket" {
  bucket = aws_s3_bucket.root_storage_bucket.id
  policy = data.databricks_aws_bucket_policy.this.json
}

resource "aws_s3_bucket_versioning" "root_bucket_versioning" {
  bucket = aws_s3_bucket.root_storage_bucket.id
  versioning_configuration {
    status = "Disabled"
  }
}

################# Databricks Workspace Creation #################

# Create a Databricks MWS workspace using the IAM role, storage configuration, and network configuration
resource "databricks_mws_workspaces" "databricks_workspace" {
  provider       = databricks.mws
  account_id     = var.databricks_account_id
  aws_region     = var.region
  workspace_name = "${local.prefix}-databricks-workspace"

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id
}

output "databricks_workspace_url" {
  value       = databricks_mws_workspaces.databricks_workspace.workspace_url
  description = "The URL of the Databricks workspace"
}

################# Grant Workspace Access to Account User #################

data "databricks_user" "me" {
  provider  = databricks.mws
  user_name = "siyam.sohag.de@gmail.com"
}

resource "databricks_mws_permission_assignment" "me" {
  provider     = databricks.mws
  workspace_id = databricks_mws_workspaces.databricks_workspace.workspace_id
  principal_id = data.databricks_user.me.id
  permissions  = ["ADMIN"]
}