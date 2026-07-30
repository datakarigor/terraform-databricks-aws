# Databricks on AWS — Detailed Learning Plan

This repository implements a sequential, hands-on learning path to manage Databricks infrastructure on AWS using Terraform. You will implement each exercise incrementally in a single `terraform/` working directory and commit after each verified apply.

This file contains: objectives, concrete implementation notes (what to add in code), verification commands, commit message suggestions, cost and safety warnings, and references — everything needed so you can implement and learn by doing.

General decisions
- Single evolving Terraform config in `terraform/` (one commit per exercise).
- Default AWS region: `eu-north-1` (change in `terraform/variables.tf` as needed).
- Resource name prefix: `dbx-learn`.
- Databricks auth pattern: prefer account-level service principal for MWS operations. Use environment variables for secrets: `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`, `DATABRICKS_ACCOUNT_ID`, and `DATABRICKS_HOST`.

Repo workflow (one exercise at a time)
1. Edit `terraform/*.tf` to implement the exercise.
2. Copy `terraform/terraform.tfvars.example` → `terraform/terraform.tfvars` and fill values (do not commit `terraform.tfvars`).
3. Run:

```bash
cd terraform
terraform init           # first time or if providers change
terraform validate
terraform plan -out=tfplan
terraform show -json tfplan | jq '.'   # optional: inspect plan as JSON
terraform apply tfplan
```

4. Verify resources in AWS and Databricks consoles (verification steps below per exercise).
5. Commit changes with the suggested commit message for the exercise.

Safety & cost notes
- Network and PrivateLink work (Exercise 3) often creates NAT Gateways and interface endpoints that bill while present — destroy promptly when done.
- Changing network-related attributes on an existing Databricks workspace may require replacement (workspace destroy/create) — read plan output carefully before applying.



Exercise 2 — Secure storage (KMS + least-privilege IAM)
Objective
- Add customer-managed KMS key for encryption of workspace storage and tighten IAM permissions.

Concrete implementation steps
- Resource: `aws_kms_key cmk` — create an asymmetric or symmetric CMK (symmetric is standard); attach a key policy that permits encryption/decryption by Databricks role and account root.
- Resource: `aws_s3_bucket_server_side_encryption_configuration` or `aws_s3_bucket` server-side encryption block — enforce default KMS encryption on `dbfs_root`.
- Resource: `databricks_mws_customer_managed_keys` — register KMS key with Databricks for the STORAGE or MANAGED_SERVICES use case.
- Update `aws_iam_role_policy` to add `kms:Decrypt` and `kms:GenerateDataKey` on the CMK ARN, keep S3 permissions least-privilege.

Verification
- `aws s3api get-bucket-encryption --bucket <name>` returns the KMS key.
- `terraform plan` should show updates to the S3 bucket (in-place) and create the KMS resource and databricks customer-managed key record.

Suggested commit message
- "Exercise 2: add customer-managed KMS for root storage"

Exercise 3 — Network isolation (private subnets + PrivateLink)
Objective
- Place Databricks workspace into private networking with interface endpoints so clusters do not use public egress.

Concrete implementation steps
- Resources: `aws_vpc`, `aws_subnet` (private subnets in two AZs), `aws_internet_gateway` (if needed), `aws_route_table`, `aws_nat_gateway` (optional), `aws_eip` (for NAT), and route table associations.
- Create gateway endpoint for S3: `aws_vpc_endpoint` (type = gateway).
- Create interface endpoints for STS, KMS, CloudWatch, Logs, and other services Databricks needs: `aws_vpc_endpoint` (type = interface). Note: AWS service endpoint names vary by region — use `aws_vpc_endpoint_service` lookups or consult AWS docs.
- Databricks: `databricks_mws_vpc_endpoint` resources register the Databricks published services for workspace and relay endpoints.
- Databricks: `databricks_mws_networks` defines the VPC/subnet/security_group mapping and references the `databricks_mws_vpc_endpoint` IDs.
- Databricks: `databricks_mws_private_access_settings` to tune private access if needed.
- Update `databricks_mws_workspaces` to reference `network_id` and `private_access_settings_id`.

Important warnings
- Changing network settings on an existing workspace commonly requires replacement. Terraform will show a plan with `-/+`. The workspace ID and URL may change. Back up any workspace configuration and verify acceptance before applying.
- NAT Gateway and interface endpoints are billable while present.

Verification
- `aws ec2 describe-vpc-endpoints --filters 'Name=vpc-id,Values=<vpc-id>'` shows endpoints and statuses.
- Validate that the workspace is accessible through the expected private path; test connectivity from an EC2 instance in the private subnet (SSM or bastion).

Suggested commit message
- "Exercise 3: private networking (VPC, private subnets, PrivateLink)"

Exercise 4 — User & token automation
Objective
- Automate creation of service principals, store their secrets in AWS Secrets Manager, and provision workspace users/groups and permissions via Terraform.

Concrete implementation steps
- `databricks_service_principal` (account-level or workspace-level depending on your use case).
- `databricks_service_principal_secret` (store secret in Databricks; consider storing the same secret value in AWS Secrets Manager using `aws_secretsmanager_secret` + `aws_secretsmanager_secret_version`).
- `databricks_group`, `databricks_user`, `databricks_group_member` to manage groups and assignments.
- `databricks_permissions` for granting access to workspace objects (clusters, jobs, etc.).

Security notes
- When creating secrets, avoid writing secret values into logs. Use `sensitive = true` for outputs in Terraform. Use `aws_secretsmanager_secret` to centralize and rotate secrets.

Verification
- Databricks Admin Console shows the service principal and groups.
- Secrets Manager stores the secret: `aws secretsmanager get-secret-value --secret-id <name>` (do not share output publicly).

Suggested commit message
- "Exercise 4: service principals and Secrets Manager integration"

Exercise 5 — Unity Catalog / metastore (advanced)
Objective
- Create and assign a Unity Catalog metastore backed by S3, then manage catalogs and schemas via Terraform.

Concrete implementation steps
- Create S3 bucket for Unity Catalog metastore storage; configure IAM role and trust policy per Databricks documentation.
- Use `databricks_metastore` (account provider), `databricks_storage_credential`, `databricks_external_location`, `databricks_metastore_assignment` to wire the metastore to the workspace.
- Use `databricks_catalog` and `databricks_schema` to manage data namespaces.

Verification
- Unity Catalog metastore appears in the Databricks Account Console.
- Create a test table in the catalog via SQL and query it to verify read/write.

Suggested commit message
- "Exercise 5: Unity Catalog metastore and catalogs/schemas"

Cleanup guidance
- Because the repository uses a single evolving state, do a final `terraform destroy` when you finish the learning path:

```bash
cd terraform
terraform destroy
```

- If a workspace replacement occurs mid-path, follow Databricks and AWS console checks, then re-run `terraform apply` for missing dependencies.

References
- Databricks Terraform provider docs (MWS & account-level): https://registry.terraform.io/providers/databrickslabs/databricks/latest
- Databricks Terraform guide for AWS: https://docs.databricks.com/dev-tools/terraform/index.html
- Unity Catalog docs: https://docs.databricks.com/data-governance/unity-catalog/index.html
- AWS docs: IAM, KMS, VPC, PrivateLink, S3 endpoint docs: https://docs.aws.amazon.com

Commit examples
- Exercise 1: "Exercise 1: simple Databricks workspace + S3 root storage"
- Exercise 2: "Exercise 2: add customer-managed KMS for root storage"
- Exercise 3: "Exercise 3: private networking (VPC + PrivateLink)"
- Exercise 4: "Exercise 4: service principals and Secrets Manager integration"
- Exercise 5: "Exercise 5: Unity Catalog metastore and catalogs"

If you'd like I can now:
- create a `.gitignore` tuned for Terraform and secrets,
- add a short `terraform/README.md` with run and cleanup commands,
- or leave the scaffolding for you to implement and I'll review PRs and help debug.

Tell me which option you prefer.
