# TWK Dev Server on AWS (Terraform)

Part 1 and 2 of the Tech With Kishky ERP DevOps series, built on AWS.

Creates a VPC, subnet, internet gateway, security group (SSH from one IP only, 80/443 open),
an Ubuntu 22.04 EC2 server with an Elastic IP, a data disk and a private versioned S3 bucket.

## Use
1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values.
2. `terraform init && terraform plan -out=tfplan && terraform apply tfplan`
3. `ssh ubuntu@$(terraform output -raw public_ip)`

Never commit `terraform.tfvars`, `tfplan` or `*.tfstate`.
