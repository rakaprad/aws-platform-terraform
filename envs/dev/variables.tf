variable "account_id" {
  description = "AWS account ID for this environment. The provider refuses to run against any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ap-southeast-3"
}

variable "state_bucket_name" {
  description = "State bucket from bootstrap/ (the CI Terraform role gets access to this environment's prefix in it)."
  type        = string
}

variable "github_repository" {
  description = "This infrastructure repository, as 'owner/name'. Its workflows may assume the Terraform role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must look like 'owner/name'."
  }
}

variable "app_github_repository" {
  description = "Application repository ('owner/name') whose main branch may assume the deploy role. Defaults to github_repository."
  type        = string
  default     = null
}

variable "create_github_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. Set false if another environment in the same account already created it."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Pick one in standard support: aws eks describe-cluster-versions."
  type        = string
  default     = "1.36"
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint, e.g. your IP as /32. Empty = private endpoint only."
  type        = list(string)
  default     = []
}

variable "cluster_admin_arns" {
  description = "IAM role/user ARNs that get cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "budget_limit_usd" {
  description = "Monthly budget in USD."
  type        = number
  default     = 250
}

variable "budget_alert_emails" {
  description = "Emails for budget alerts. Empty = no budget is created."
  type        = list(string)
  default     = []
}
