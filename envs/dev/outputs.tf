output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "nat_public_ips" {
  description = "Egress IPs of the private subnets."
  value       = module.vpc.nat_public_ips
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "update_kubeconfig_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "ecr_repository_url" {
  description = "Where to push images."
  value       = module.ecr.repository_url
}

output "terraform_role_arn" {
  description = "role-to-assume for this repo's Terraform workflow (GitHub variable DEV_TF_ROLE_ARN)."
  value       = module.github_oidc.terraform_role_arn
}

output "deploy_role_arn" {
  description = "role-to-assume for the application's build/deploy workflow."
  value       = module.github_oidc.deploy_role_arn
}
