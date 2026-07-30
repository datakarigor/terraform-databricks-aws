Exercise 1 — Simple workspace (default VPC)

Objective
- Stand up a minimal Databricks workspace using Databricks MWS resources and S3-backed root storage. This exercise focuses on MWS account-level resources that are required to provision a workspace: storage, credentials, and the workspace resource itself.

What you'll add (high level)
- An S3 bucket for DBFS root storage (`aws_s3_bucket`).
- A cross-account IAM role that Databricks can assume (`aws_iam_role`).
- A minimal inline IAM policy scoped to the S3 bucket (`aws_iam_role_policy`).
- Databricks account-level resources: `databricks_mws_credentials`, `databricks_mws_storage_configurations`, and `databricks_mws_workspaces`.

Step-by-step implementation (copy into `terraform/` files)

1) Variables — add to `terraform/variables.tf`

```hcl
variable "region" { type = string, default = "eu-north-1" }
variable "prefix" { type = string, default = "dbx-learn" }
variable "environment" { type = string, default = "dev" }
variable "databricks_account_id" { type = string }
variable "s3_root_bucket_name" { type = string, default = "" }
```

2) Random suffix helper (optional) — add to your main TF file

```hcl
resource "random_id" "suffix" { byte_length = 4 }
locals { name_prefix = "${var.prefix}-${var.environment}" }
```

3) S3 bucket — `aws_s3_bucket.dbfs_root`

```hcl
resource "aws_s3_bucket" "dbfs_root" {
  bucket = var.s3_root_bucket_name != "" ? var.s3_root_bucket_name : "${local.name_prefix}-root-${random_id.suffix.hex}"
  tags = { Name = "${local.name_prefix}-dbfs-root" }
}
```

4) IAM role Databricks will assume — `aws_iam_role.databricks_cross_account`

Notes: Databricks publishes the required trust principal and external ID pattern for account-level roles; copy the exact JSON from their docs for your account region/product. The example below is a placeholder — replace it with the correct trust principal from Databricks docs.

```hcl
resource "aws_iam_role" "databricks_cross_account" {
  name = "${local.name_prefix}-dbx-cross-account-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "databricks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
```

5) IAM inline policy scoping S3 access — `aws_iam_role_policy.databricks_basic`

Grant only the necessary S3 actions for the root bucket:

```hcl
resource "aws_iam_role_policy" "databricks_basic" {
  name = "${local.name_prefix}-dbx-basic"
  role = aws_iam_role.databricks_cross_account.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.dbfs_root.arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.dbfs_root.arn}/*" }
    ]
  })
}
```

6) Databricks MWS credentials — `databricks_mws_credentials`

```hcl
resource "databricks_mws_credentials" "mws_creds" {
  provider = databricks.mws
  credentials_name = "${local.name_prefix}-mws-creds"
  role_arn = aws_iam_role.databricks_cross_account.arn
}
```

7) Databricks storage configuration — `databricks_mws_storage_configurations`

```hcl
resource "databricks_mws_storage_configurations" "storage" {
  provider = databricks.mws
  storage_configuration_name = "${local.name_prefix}-storage"
  credentials_id = databricks_mws_credentials.mws_creds.credentials_id
  root_bucket_info { bucket_name = aws_s3_bucket.dbfs_root.bucket }
}
```

8) Databricks workspace — `databricks_mws_workspaces`

```hcl
resource "databricks_mws_workspaces" "workspace" {
  provider = databricks.mws
  account_id = var.databricks_account_id
  workspace_name = "${local.name_prefix}-workspace"
  deployment_name = "${local.name_prefix}-deployment"
  credentials_id = databricks_mws_credentials.mws_creds.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.storage.storage_configuration_id
  region = var.region
}
```

9) Outputs — add to `terraform/outputs.tf`

```hcl
output "workspace_name" { value = databricks_mws_workspaces.workspace.workspace_name }
output "workspace_deployment_name" { value = databricks_mws_workspaces.workspace.deployment_name }
output "s3_bucket_name" { value = aws_s3_bucket.dbfs_root.bucket }
```

Verification & run commands

Run these locally after you set environment variables and `terraform/terraform.tfvars`:

```bash
cd terraform
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Post-apply verification

- Databricks Account Console → Workspaces: workspace should appear and show provisioning status.
- Check bucket exists:

```bash
aws s3api get-bucket-location --bucket $(terraform output -raw s3_bucket_name)
aws s3 ls s3://$(terraform output -raw s3_bucket_name)
```

- Check IAM role:

```bash
aws iam get-role --role-name "${local.name_prefix}-dbx-cross-account-role"
```

Commit guidance

After successful apply and manual verification, commit your changes:

```bash
git add terraform/*.tf
git commit -m "Exercise 1: simple Databricks workspace + S3 root storage"
```

Troubleshooting (common issues you'll hit)

- AccessDenied when Databricks assumes the role: verify the `assume_role_policy` exactly matches Databricks documentation (external ID, principal). Databricks often provides an `ExternalId` requirement; ensure that is included.
- Provider auth failures: ensure `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`, `DATABRICKS_ACCOUNT_ID`, and `DATABRICKS_HOST` are set in your environment before running `terraform plan`.
- Unexpected workspace replacements: inspect plan JSON for `change.actions` showing `delete`+`create`. Network/storage id changes commonly cause replacement.

Safety & cleanup

- Destroy when finished if you don't want charges:

```bash
cd terraform
terraform destroy
```

Next steps (after you implement)

- Paste your `terraform plan` output here (or the relevant `terraform show -json tfplan` snippet) and I will review for risky replacements and IAM trust issues before you `apply`.
- If you'd like, I can produce a minimal starter `databricks_ex1.tf` file for you to review rather than writing it fully from scratch.

Suggested commit message
- "Exercise 1: simple Databricks workspace + S3 root storage"

-- End of Exercise 1 plan