resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_51:Tag immutability is a per-environment choice (var.immutable_tags): on in prod, off in dev for fast iteration on e.g. :latest

  name                 = var.name
  image_tag_mutability = var.immutable_tags ? "IMMUTABLE" : "MUTABLE"
  force_delete         = var.force_delete

  # Basic scanning: OS package CVEs on every push, results in the console / API.
  image_scanning_configuration {
    scan_on_push = true
  }

  # KMS with the AWS-managed aws/ecr key unless a customer-managed key is given.
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the ${var.keep_last_images} most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
