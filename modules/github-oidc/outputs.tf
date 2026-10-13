output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider."
  value       = local.oidc_provider_arn
}

output "terraform_role_arn" {
  description = "role-to-assume for the Terraform workflow."
  value       = aws_iam_role.terraform.arn
}

output "deploy_role_arn" {
  description = "role-to-assume for application build/deploy workflows."
  value       = aws_iam_role.deploy.arn
}
