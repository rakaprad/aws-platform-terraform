variable "region" {
  description = "Region for the state bucket."
  type        = string
  default     = "ap-southeast-3"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state, e.g. <account-id>-tfstate-ap-southeast-3."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 lowercase letters, digits, dots or hyphens."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How long old state versions are kept before they are deleted."
  type        = number
  default     = 90
}
