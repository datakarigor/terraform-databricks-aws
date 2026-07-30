
# Fetch the AWS assume role policy for Databricks cross-account access
data "databricks_aws_assume_role_policy" "this" {
  provider    = databricks.mws
  external_id = var.databricks_account_id
}

# Create an IAM role for Databricks cross-account access
resource "aws_iam_role" "databricks_cross_account" {
  name               = "${var.prefix}-${var.environment}-databricks-cross-account-role"
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
  name   = "${var.prefix}-${var.environment}-databricks-cross-account-policy"
  role   = aws_iam_role.databricks_cross_account.id
  policy = data.databricks_aws_crossaccount_policy.this.json
}

# Create Databricks MWS credentials for the IAM role
resource "databricks_mws_credentials" "this" {
  provider         = databricks.mws
  role_arn         = aws_iam_role.databricks_cross_account.arn
  credentials_name = "${var.prefix}-${var.environment}-databricks-cross-account-credentials"
  depends_on       = [aws_iam_role_policy.this, aws_iam_role.databricks_cross_account]
}

# Root S3 bucket for DBFS inside Databricks workspace. This bucket is used to store the root of the DBFS filesystem.
resource "aws_s3_bucket" "dbfs_root" {
  bucket = "${var.prefix}-${var.environment}-dbfs-root-bucket"
  tags   = var.tags
}

# Create a Databricks storage configuration for the S3 bucket
resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks.mws
  account_id                 = var.databricks_account_id
  bucket_name                = aws_s3_bucket.dbfs_root.bucket
  storage_configuration_name = "${var.prefix}-${var.environment}-databricks-storage-configuration"
}

resource "databricks_mws_workspaces" "databricks_workspace" {
  provider       = databricks.mws
  account_id     = var.databricks_account_id
  aws_region     = var.databricks_aws_region
  workspace_name = "${var.prefix}-${var.environment}-databricks-workspace"

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
}