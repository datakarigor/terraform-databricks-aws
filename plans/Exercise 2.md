Exercise 1 — Completed items and next steps

Objective
- Stand up a minimal Databricks workspace using Databricks MWS resources and S3-backed root storage.

Status: In-progress (missing IAM permission adjustments). The Terraform configuration contains the required resources (S3 bucket, IAM role, IAM policy, databricks_mws_credentials, databricks_mws_storage_configurations, databricks_mws_workspaces) but Databricks credential/workspace validation failed due to missing EC2/VPC permissions.

Exercise 1 - Actions to finish
1. IAM permissions: expand `aws_iam_role_policy.this` to include the following minimal EC2/VPC actions so Databricks can validate credentials and create networking when provisioning a workspace:
   - ec2:CreateVpc, ec2:DeleteVpc
   - ec2:CreateInternetGateway, ec2:AttachInternetGateway, ec2:DeleteInternetGateway
   - ec2:AllocateAddress, ec2:ReleaseAddress
   - ec2:CreateNatGateway, ec2:DeleteNatGateway
   - ec2:CreateRouteTable, ec2:DeleteRouteTable, ec2:AssociateRouteTable, ec2:DisassociateRouteTable
   - ec2:CreateVpcEndpoint, ec2:DeleteVpcEndpoints
   - ec2:Describe*, ec2:CreateTags, ec2:DescribeVpcs, ec2:DescribeSubnets

   Note: If you prefer not to grant create/delete permissions, skip to Option B below.

2. Ensure `databricks_mws_credentials.this` has explicit `depends_on` for the IAM role and IAM role policy to avoid propagation timing issues.

3. Re-run `terraform plan` and `terraform apply`. If Databricks reports additional missing actions, add the exact actions listed in the error to the IAM policy.

Option B (more secure): Configure the workspace to use existing VPC/subnets so Databricks does not need create/delete VPC resources. This requires adding variables and passing `vpc_id` and subnet IDs to the `databricks_mws_workspaces` resource.

Files touched (already present)
- terraform/main.tf — resources and `depends_on` adjustments
- terraform/variables.tf — existing variables; add `s3_root_bucket_name` if desired


Exercise 2 — VPC-backed workspace (Plan)

Goal
- Provision a Databricks workspace that uses an existing VPC and subnet IDs so Databricks does not need to create or delete network resources.

Why
- Avoids granting Databricks broad EC2/VPC create/delete permissions.
- Fits secure, production-like environments where networking is centrally managed.

Steps
1. Add variables to `terraform/variables.tf`:
   - `existing_vpc_id` (string, default "")
   - `existing_public_subnet_ids` (list(string), default = [])
   - `existing_private_subnet_ids` (list(string), default = [])
   - `existing_route_table_ids` (optional list)

2. Update `databricks_mws_workspaces` in `main.tf` to accept and pass the network configuration fields required by the Databricks MWS provider (confirm exact field names in provider docs). Typical fields:
   - `vpc_id` or `network` block
   - `public_subnet_ids` / `private_subnet_ids` or provider-specific equivalents
   - optionally `customer_managed_keys`, `network_security_group_ids` as needed

3. Narrow IAM permissions on the cross-account role to remove create/delete VPC actions. Keep only `Describe*` and any attach/ENI actions required to operate inside your VPC.

4. Test locally:
   - `terraform init`
   - `terraform validate`
   - `terraform plan`
   - `terraform apply` (when ready)

5. Verification
   - Confirm workspace resources in Databricks console use the provided VPC/subnets.
   - Inspect AWS console to ensure no new VPC/IGW/NATs were created by Databricks.

Files to add/update for Exercise 2
- terraform/variables.tf — add network variables
- terraform/main.tf — update workspace resource network fields
- optionally terraform/network.tf — if you choose to create VPC/subnets in code


Next steps I can take (if you ask me to proceed)
- Draft the exact IAM policy JSON containing the minimal extra EC2 permissions for Exercise 1.
- Draft example `databricks_mws_workspaces` network block for Exercise 2 using provider docs.


Notes
- Always re-run `terraform plan` before `apply` and inspect the actions carefully.
- If Databricks provider errors list specific missing actions, update the IAM policy with those exact actions rather than broad wildcards.

Exercise 2 — Detailed step-by-step guide (practice implementation)

Context & goal
- You will create all required VPC networking (VPC, public/private subnets, IGW, NAT, route tables) inside `main.tf`, then provision a Databricks workspace that uses that network. This exercise intentionally has you implement networking so you learn how Databricks interacts with AWS networking.

High-level steps (do these in order and run `terraform plan` often)
1. Add network variables to `terraform/variables.tf`.
2. Implement VPC creation in `terraform/main.tf`.
3. Add public subnets + IGW + public route table and associations.
4. Add private subnets + NAT EIP + NAT gateway + private route table and associations.
5. Expand the IAM role policy so Databricks can create/manage networking and access S3.
6. Ensure `databricks_mws_credentials` has `depends_on` for the IAM role and inline policies.
7. Create the Databricks storage configuration (S3) and then create the `databricks_mws_workspaces` resource referencing your VPC/subnets.
8. Add outputs and verify with `terraform plan` and `terraform apply`.

Concrete changes to make

1) `variables.tf` additions
- Add these variables (copy/paste):

```hcl
variable "vpc_cidr" { type = string, default = "10.50.0.0/16" }
variable "public_subnet_cidrs" { type = list(string), default = ["10.50.0.0/24"] }
variable "private_subnet_cidrs" { type = list(string), default = ["10.50.1.0/24"] }
variable "enable_nat" { type = bool, default = true }
variable "nat_eip_count" { type = number, default = 1 }
```

2) VPC resource (in `main.tf`) — create a VPC:

```hcl
resource "aws_vpc" "main" {
   cidr_block = var.vpc_cidr
   tags = merge(var.tags, { Name = "${var.prefix}-${var.environment}-vpc" })
}
```

3) Internet Gateway + public subnets + public route table

```hcl
resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main.id, tags = var.tags }

resource "aws_subnet" "public" {
   for_each = toset(var.public_subnet_cidrs)
   vpc_id = aws_vpc.main.id
   cidr_block = each.value
   map_public_ip_on_launch = true
   tags = merge(var.tags, { Name = "${var.prefix}-${var.environment}-public-${replace(each.value, "/", "-")}" })
}

resource "aws_route_table" "public_rt" {
   vpc_id = aws_vpc.main.id
   route { cidr_block = "0.0.0.0/0", gateway_id = aws_internet_gateway.igw.id }
   tags = var.tags
}

resource "aws_route_table_association" "public_assoc" {
   for_each = aws_subnet.public
   subnet_id = each.value.id
   route_table_id = aws_route_table.public_rt.id
}
```

4) Private subnets + NAT (optional but recommended)

```hcl
resource "aws_subnet" "private" {
   for_each = toset(var.private_subnet_cidrs)
   vpc_id = aws_vpc.main.id
   cidr_block = each.value
   map_public_ip_on_launch = false
   tags = merge(var.tags, { Name = "${var.prefix}-${var.environment}-private-${replace(each.value, "/", "-")}" })
}

resource "aws_eip" "nat_eip" { count = var.enable_nat ? var.nat_eip_count : 0, vpc = true }

resource "aws_nat_gateway" "nat" {
   count = var.enable_nat ? var.nat_eip_count : 0
   allocation_id = aws_eip.nat_eip[count.index].id
   subnet_id = element(values(aws_subnet.public), 0)
   depends_on = [aws_internet_gateway.igw]
   tags = var.tags
}

resource "aws_route_table" "private_rt" {
   count = var.enable_nat ? 1 : 0
   vpc_id = aws_vpc.main.id
   route { cidr_block = "0.0.0.0/0", nat_gateway_id = var.enable_nat ? aws_nat_gateway.nat[0].id : null }
   tags = var.tags
}

resource "aws_route_table_association" "private_assoc" {
   for_each = aws_subnet.private
   subnet_id = each.value.id
   route_table_id = var.enable_nat ? aws_route_table.private_rt[0].id : aws_route_table.public_rt.id
}
```

5) IAM policy additions
- Expand the IAM role policy attached to `aws_iam_role.databricks_cross_account` to include S3 actions scoped to your DBFS bucket and the EC2/VPC actions listed in Exercise 1. Keep the Databricks-provided crossaccount policy as-is and attach an additional inline policy (so you don't edit provider data). Example minimal statement (merge into JSON):

```hcl
resource "aws_iam_role_policy" "extra" {
   name = "${var.prefix}-${var.environment}-databricks-extra-policy"
   role = aws_iam_role.databricks_cross_account.id
   policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
         { Effect = "Allow", Action = ["s3:ListBucket","s3:GetObject","s3:PutObject","s3:DeleteObject"], Resource = [aws_s3_bucket.dbfs_root.arn, "${aws_s3_bucket.dbfs_root.arn}/*"] },
         { Effect = "Allow", Action = ["ec2:CreateVpc","ec2:DeleteVpc","ec2:CreateInternetGateway","ec2:AttachInternetGateway","ec2:DeleteInternetGateway","ec2:AllocateAddress","ec2:ReleaseAddress","ec2:CreateNatGateway","ec2:DeleteNatGateway","ec2:CreateRouteTable","ec2:DeleteRouteTable","ec2:AssociateRouteTable","ec2:DisassociateRouteTable","ec2:CreateVpcEndpoint","ec2:DeleteVpcEndpoints","ec2:Describe*","ec2:CreateTags","ec2:DescribeVpcs","ec2:DescribeSubnets"], Resource = "*" }
      ]
   })
}
```

6) Ensure `databricks_mws_credentials` depends on the role and both policies (you already added `depends_on`).

7) Databricks storage configuration and workspace
- Keep your `aws_s3_bucket.dbfs_root` and create `databricks_mws_storage_configurations` as you already have.
- When creating `databricks_mws_workspaces`, pass the network information to the provider. The provider's exact field names may be `vpc_id`, `public_subnet_ids`, `private_subnet_ids` or a `network` nested block. Try adding these fields (example below) and run `terraform plan` — adjust if provider reports unknown attributes.

Example (try, then adjust to provider feedback):

```hcl
resource "databricks_mws_workspaces" "databricks_workspace" {
   provider       = databricks.mws
   account_id     = var.databricks_account_id
   aws_region     = var.databricks_aws_region
   workspace_name = "${var.prefix}-${var.environment}-databricks-workspace"

   credentials_id           = databricks_mws_credentials.this.credentials_id
   storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id

   # network info - provider may require slightly different names or nested blocks
   vpc_id = aws_vpc.main.id
   public_subnet_ids  = [for s in aws_subnet.public : s.id]
   private_subnet_ids = [for s in aws_subnet.private : s.id]
}
```

8) Outputs — add outputs to help verify

```hcl
output "vpc_id" { value = aws_vpc.main.id }
output "public_subnet_ids" { value = [for s in aws_subnet.public : s.id] }
output "private_subnet_ids" { value = [for s in aws_subnet.private : s.id] }
output "dbfs_bucket" { value = aws_s3_bucket.dbfs_root.bucket }
output "workspace_name" { value = databricks_mws_workspaces.databricks_workspace.workspace_name }
```

Verification checklist
- After adding each major block run:

```bash
cd terraform
terraform init    # only once or when provider changes
terraform plan
```

- If `databricks_mws_credentials` fails validation, add the exact actions the error lists into the IAM policy and retry.
- If `databricks_mws_workspaces` reports unknown attributes, consult the Databricks provider docs or paste the error here and adjust field names accordingly.

Safety & cleanup
- NAT gateways and EIPs can cost money; run `terraform destroy` when finished.

Learning tips
- Implement blocks incrementally — first VPC+IGW+public subnets, verify. Then private subnets and NAT, verify. Then IAM changes, then Databricks account resources, then workspace.
- Keep commits small so you can revert easily.

When you're ready, tell me which block you added and paste `terraform plan` output if you hit errors — I'll help fix them step-by-step.


