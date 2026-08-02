# terraform/outputs.tf

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.demo.id
}

output "instance_public_ip" {
  description = "EC2 Public IP"
  value       = aws_instance.demo.public_ip
}

output "environment" {
  description = "Environment"
  value       = var.environment
}
