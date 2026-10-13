variable "name" {
  description = "Name prefix (e.g. platform-dev). Role names start with it, and the Terraform role may only manage IAM roles that start with it."
  type        = string
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Only one can exist per account: set false in the second environment if dev and prod share an account."
  type        = bool
  default     = true
}

variable "terraform_role_subjects" {
  description = "Allowed GitHub OIDC `sub` claims for the Terraform role, e.g. repo:owner/name:pull_request and repo:owner/name:environment:dev."
  type        = list(string)

  validation {
    condition     = length(var.terraform_role_subjects) > 0 && alltrue([for s in var.terraform_role_subjects : can(regex("^repo:[A-Za-z0-9-]+/[A-Za-z0-9._-]+:.+$", s))])
    error_message = "Each subject must be 'repo:<owner>/<name>:<context>' with no wildcard in owner or name."
  }
}

variable "deploy_role_subjects" {
  description = "Allowed GitHub OIDC `sub` claims for the deploy role, e.g. repo:owner/app:ref:refs/heads/main."
  type        = list(string)

  validation {
    condition     = length(var.deploy_role_subjects) > 0 && alltrue([for s in var.deploy_role_subjects : can(regex("^repo:[A-Za-z0-9-]+/[A-Za-z0-9._-]+:.+$", s))])
    error_message = "Each subject must be 'repo:<owner>/<name>:<context>' with no wildcard in owner or name."
  }
}

variable "ecr_repository_arn" {
  description = "The one ECR repository the deploy role may push to."
  type        = string
}

variable "eks_cluster_name" {
  description = "The one EKS cluster the deploy role may describe (to build a kubeconfig)."
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform state (from bootstrap/)."
  type        = string
}

variable "state_key_prefix" {
  description = "State key prefix this environment's Terraform role may read and write, e.g. envs/dev."
  type        = string

  validation {
    condition     = !startswith(var.state_key_prefix, "/") && !endswith(var.state_key_prefix, "/") && length(var.state_key_prefix) > 0
    error_message = "state_key_prefix must be non-empty with no leading or trailing slash."
  }
}
