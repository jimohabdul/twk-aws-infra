# Building and Locking Down a Cloud Dev Server on AWS with Terraform

*Parts 1 and 2 of the Tech With Kishky ERP DevOps series, rebuilt on AWS. Written from what I actually ran, including the mistakes.*

<!-- TODO: add your name, date and a one-line intro in your own words -->

## What I built

A developer machine in the cloud, described entirely in code. One `terraform apply` creates:

- a private network (VPC, subnet, internet gateway, route table)
- a firewall (security group) that allows SSH **only from my own IP**, plus ports 80 and 443
- an Ubuntu 22.04 server (EC2) with a fixed public address (Elastic IP)
- a second data disk (EBS)
- a private, versioned, encrypted S3 bucket for state and backups later

Then I locked the server down: a normal user, key-only SSH, no root login, no passwords.

The original series is written for Huawei Cloud. I had no Huawei account, only AWS, so I translated each piece. The Terraform ideas are the same on every cloud. Only the provider and resource names change.

## Huawei to AWS: what each piece became

| Piece | Huawei Cloud | AWS |
|---|---|---|
| Network | VPC, subnet | `aws_vpc`, `aws_subnet`, plus `aws_internet_gateway` and a route table (AWS needs these explicitly) |
| Firewall | Security group | `aws_security_group` |
| Server | ECS | `aws_instance` |
| Fixed address | EIP | `aws_eip` |
| Disks | EVS | `aws_ebs_volume`, `aws_volume_attachment` |
| Bucket | OBS | `aws_s3_bucket` (+ versioning, encryption, public access block) |
| First login user | `root` | `ubuntu` |
| Credentials | `HW_ACCESS_KEY` / `HW_SECRET_KEY` | AWS CLI credentials |

## Before touching Terraform: account safety

- Confirmed I was using an IAM user, not the root account: `aws sts get-caller-identity` showed `user/...`, not `root`.
- Turned on MFA for the root user and my IAM user.
- Created a monthly budget alert so a forgotten server cannot surprise me.
- Kept secrets out of Git from the start (`.gitignore` excludes `terraform.tfvars`, `*.tfstate` and `tfplan`).

<!-- TODO: screenshot of your budget alert or MFA page (hide your account ID) -->

## Part 1: building the server

### Project layout

```text
twk-aws/
  main.tf                  # all resources
  variables.tf             # inputs (region, ssh_cidr, instance_type, ...)
  outputs.tf               # public IP, ssh command, bucket name
  terraform.tfvars         # my real values (NOT in Git)
  terraform.tfvars.example # safe template (in Git)
  .gitignore
```

### The workflow

```bash
terraform fmt        # tidy formatting
terraform init       # download the AWS provider, create the lock file
terraform validate   # check the configuration is valid
terraform plan -out=tfplan   # preview, changes nothing
terraform apply tfplan       # build exactly what the plan showed
```

The most important habit is **reading the plan before applying**. In mine I checked three things:

1. `Plan: 15 to add, 0 to change, 0 to destroy`, so nothing existing would be touched.
2. The SSH rule was open to my own `/32` address only, never `0.0.0.0/0`.
3. Disks were encrypted, the instance required IMDSv2, and the bucket blocked public access.

I also added a validation rule in `variables.tf` that rejects `0.0.0.0/0` for SSH, so I cannot open the door to the whole internet by accident.

<!-- TODO: screenshot of the end of `terraform plan` and of `Apply complete!` -->

## Errors I hit (and what they taught me)

### 1. Empty files that still "validated"

I copied three `.tf` files into WSL and two of them were empty. `terraform validate` still said **Success**, because an empty configuration is technically valid. The giveaway was a warning that my `terraform.tfvars` values had no matching variable.

**Lesson:** "valid" does not mean "complete". Check `wc -l *.tf` and read warnings.

### 2. The Free Tier size limit

Apply built 11 resources, then failed on the server:

```text
InvalidParameterCombination: The specified instance type is not eligible for Free Tier.
```

My account was on the Free Tier plan, which only allows certain instance types. I listed the allowed ones:

```bash
aws ec2 describe-instance-types --region us-east-1 \
  --filters Name=free-tier-eligible,Values=true \
  --query "InstanceTypes[].[InstanceType,VCpuInfo.DefaultVCpus,MemoryInfo.SizeInMiB]" \
  --output table
```

I switched from `t3.medium` to `t3.small` (2 vCPU, 2 GB), re-ran `plan` (it correctly showed only the 4 missing resources) and applied again.

**Lesson:** a failed apply is normal and safe. Terraform kept the 11 resources in state and only created what was missing.

### 3. A terminal that stopped responding

The AWS CLI opened its output in a pager (`less`) and my typing seemed to do nothing. Pressing `q` exits it, and this turns it off for good:

```bash
aws configure set cli_pager ""
```

### 4. Pasted commands that failed with `command not found`

Pasting added invisible characters (`[200~`) to my command. Typing it by hand worked. Turning off bracketed paste fixes it:

```bash
bind 'set enable-bracketed-paste off'
```

### 5. Running a command on the wrong machine

I ran my SSH shortcut commands on the **server** instead of my laptop, so `cd ~/twk-aws` failed there. It was harmless, but I now check the prompt (`user@host`) before every command.

## Part 2: locking the front door

A fresh server accepts logins from a powerful account. The goal is a normal user, sudo, and key-only SSH, in an order that cannot lock me out.

On AWS the default user is `ubuntu` and root SSH login is already blocked, so my steps differed slightly from the Huawei version. I copied the SSH key from `/home/ubuntu/.ssh/authorized_keys`, not from root's.

```bash
sudo adduser --disabled-password --gecos "" twk
sudo usermod -aG sudo twk
echo "twk ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/twk
sudo chmod 440 /etc/sudoers.d/twk
sudo visudo -cf /etc/sudoers.d/twk          # must say: parsed OK
sudo install -d -m 700 -o twk -g twk /home/twk/.ssh
sudo install -m 600 -o twk -g twk /home/ubuntu/.ssh/authorized_keys /home/twk/.ssh/authorized_keys
```

Why these details matter:

- `usermod -aG` (with `-a`) **appends** to groups. Without `-a`, the user loses every other group.
- `visudo -cf` checks a sudoers file before it is used. A typo there can break `sudo` for everyone.
- SSH silently ignores keys with loose permissions, so the `700` and `600` modes are required.

### Test first, lock second

Before changing any SSH setting, I opened a **second terminal** and logged in as `twk`, then ran `sudo whoami` and got `root` without a password. Only then did I harden SSH, keeping the first session open as a safety net.

```text
# /etc/ssh/sshd_config.d/00-twk-hardening.conf
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
```

The `00-` prefix makes this file load first. In SSH config the first value wins, so a file added later by the cloud image cannot override it.

```bash
sudo sshd -t                 # syntax check, prints nothing if fine
sudo systemctl reload ssh    # apply without cutting my session
```

### Proving the door is locked

```bash
ssh twk@<server-ip> whoami                        # twk
ssh -o PubkeyAuthentication=no twk@<server-ip>    # Permission denied (publickey)
ssh root@<server-ip>                              # Permission denied (publickey)
```

<!-- TODO: screenshot of these three results -->

A shortcut in `~/.ssh/config` on my laptop means I now just run `ssh twk-dev`.

## Cost and safety habits

- The server, disks and Elastic IP cost money while they exist. `terraform destroy` removes everything, and `terraform apply` rebuilds it.
- Terraform's **state file** is how it remembers what it built. I back it up (`terraform.tfstate`) until it moves to S3 in a later part.
- `terraform.tfvars`, `tfplan` and `*.tfstate` never go to Git.

## What I learned

1. Infrastructure as code means my server is text in Git, not clicks in a console.
2. Always read the plan. It is the cheapest place to catch a mistake.
3. Failed applies are recoverable when state is intact.
4. Test the new door before closing the old one.
5. The same ideas carry across clouds. Only names and defaults change.

## What comes next

Part 3: formatting and mounting the data disk, adding swap, and enabling automatic security updates.

---

*Code: https://github.com/jimohabdul/twk-aws-infra*
*Based on the Tech With Kishky ERP series.*