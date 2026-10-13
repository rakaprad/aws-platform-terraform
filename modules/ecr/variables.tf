variable "name" {
  description = "Repository name, e.g. platform-dev/app."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.name)) && length(var.name) >= 2 && length(var.name) <= 256
    error_message = "name must be a valid ECR repository name (lowercase, digits, . _ - and / separators)."
  }
}

variable "immutable_tags" {
  description = "Reject pushes that would overwrite an existing tag (recommended for prod: a tag always means the same image)."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN. null = the AWS-managed aws/ecr key."
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Allow Terraform to delete the repository even if it still contains images."
  type        = bool
  default     = false
}

variable "keep_last_images" {
  description = "Number of most recent images to keep; older ones are expired."
  type        = number
  default     = 30

  validation {
    condition     = var.keep_last_images >= 1
    error_message = "keep_last_images must be at least 1."
  }
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images (e.g. replaced by a re-push) are expired."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1
    error_message = "untagged_expiry_days must be at least 1."
  }
}
