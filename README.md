# terraform-databricks-aws

Terraform project that provisions a Databricks workspace on AWS (E2, customer-managed VPC), including:

- A dedicated VPC (public + private subnets, NAT gateway, S3/STS/Kinesis VPC endpoints)
- IAM cross-account role + policy for Databricks
- An S3 root (DBFS) bucket with encryption, versioning, and public-access blocked
- Databricks MWS credentials, storage configuration, network, and workspace resources
- Account-level permission assignment to grant workspace access to a user

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.x
- [direnv](https://direnv.net/) (used to load environment variables from `.envrc`)
- AWS credentials with permissions for VPC, IAM, S3, and STS in the target account/region
- A Databricks account (Account Console) and a service principal (`client_id` / `client_secret`) with account admin access
- An S3 bucket for the Terraform state backend (see [terraform/backend.tf](terraform/backend.tf))

## Setup

1. Copy the example env file and fill in your own values (never commit the real `.envrc`):
   ```bash
   cp terraform/.envrc.example terraform/.envrc
   ```
2. Edit `terraform/.envrc` with your Databricks service principal credentials and account ID.
3. Allow direnv to load the file and hook it into your shell:
   ```bash
   direnv allow
   eval "$(direnv hook zsh)"
   ```
4. Select/export your AWS credentials profile (access keys or SSO), e.g.:
   ```bash
   export AWS_PROFILE=<your-profile-name>
   aws sts get-caller-identity   # sanity check
   ```

## Usage

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Get the workspace URL once applied:
```bash
terraform output databricks_workspace_url
```

Tear everything down:
```bash
terraform destroy
```

## Repository structure

```
terraform/
  backend.tf      # S3 remote state backend
  providers.tf    # AWS + Databricks (+ time) provider configuration
  variables.tf    # Input variables (region, prefix, Databricks account, etc.)
  main.tf         # VPC, IAM, S3, and Databricks MWS resources
plans/            # Design notes / exercises used while building this out
```

## Notes

- `var.region` drives both the AWS provider/VPC and the Databricks workspace's `aws_region` — keep these in sync (see [Databricks supported regions](https://docs.databricks.com/aws/en/resources/supported-regions)).
- A `time_sleep` resource is used before creating Databricks credentials to work around IAM policy propagation delays — see the [official Databricks AWS workspace guide](https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/aws-workspace) for details.
- Real secrets belong only in your local `terraform/.envrc` (gitignored) — never commit credentials, `.tfstate`, or `.tfvars` files.