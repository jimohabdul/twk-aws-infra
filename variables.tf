variable "region" {
  description = "AWS region to build in"
  type        = string
  default     = "us-east-1"
}

variable "ssh_cidr" {
  description = "Your public IP with /32. Only this address can SSH in."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_cidr, 0)) && var.ssh_cidr != "0.0.0.0/0"
    error_message = "Use your own IP in CIDR form, like 203.0.113.7/32. 0.0.0.0/0 is not allowed."
  }
}

variable "ssh_public_key_path" {
  description = "Path to your SSH PUBLIC key (the .pub file)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "instance_type" {
  description = "Server size"
  type        = string
  default     = "t3.medium"
}

variable "data_disk_gb" {
  description = "Size of the second disk in GB"
  type        = number
  default     = 30
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
}
