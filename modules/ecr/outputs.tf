output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN (used to scope push permissions)."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "Registry URL to tag and push images to."
  value       = aws_ecr_repository.this.repository_url
}
