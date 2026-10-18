output "public_ip" {
  description = "Fixed public address of the server"
  value       = aws_eip.dev.public_ip
}

output "ssh_command" {
  description = "Copy and run this to log in"
  value       = "ssh ubuntu@${aws_eip.dev.public_ip}"
}

output "bucket_name" {
  value = aws_s3_bucket.main.bucket
}
