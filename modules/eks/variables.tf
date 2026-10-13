variable "name" {
  description = "Cluster name, also used as a prefix for IAM roles, KMS alias and log group."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,99}$", var.name))
    error_message = "name must start with a letter and contain only letters, digits and hyphens (max 100)."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes minor version (e.g. 1.36). Check `aws eks describe-cluster-versions` for versions in standard support."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like 1.36."
  }
}

variable "support_type" {
  description = "EKS upgrade policy. STANDARD = cluster is auto-upgraded at end of standard support; EXTENDED = pay extra to stay on an old version."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control-plane ENIs and the node group (at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Empty list = private endpoint only (reach it via VPN / bastion / SSM)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "public_access_cidrs must be valid CIDRs and must not include 0.0.0.0/0."
  }
}

variable "deletion_protection" {
  description = "Block cluster deletion until this is set to false and applied."
  type        = bool
  default     = true
}

variable "enabled_log_types" {
  description = "Control-plane log types sent to CloudWatch Logs."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition     = alltrue([for t in var.enabled_log_types : contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)])
    error_message = "Valid log types: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "log_retention_days" {
  description = "Retention for the control-plane log group, in days."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

variable "access_entries" {
  description = <<-EOT
    IAM principals that get Kubernetes access, keyed by a short name.
    policy: an EKS access policy name (AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy).
    namespaces: limit the policy to these namespaces; empty = whole cluster.
  EOT
  type = map(object({
    principal_arn = string
    policy        = optional(string, "AmazonEKSClusterAdminPolicy")
    namespaces    = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for e in values(var.access_entries) : contains(["AmazonEKSClusterAdminPolicy", "AmazonEKSAdminPolicy", "AmazonEKSEditPolicy", "AmazonEKSViewPolicy"], e.policy)])
    error_message = "policy must be one of AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy, AmazonEKSViewPolicy."
  }
}

variable "node_instance_types" {
  description = "Instance types for the managed node group (more than one only makes sense with SPOT)."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min_size" {
  description = "Minimum number of nodes."
  type        = number
  default     = 1
}

variable "node_desired_size" {
  description = "Initial number of nodes (ignored after creation so an autoscaler can own it)."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

variable "node_disk_size" {
  description = "Root EBS volume size per node, in GiB (gp3, encrypted)."
  type        = number
  default     = 30

  validation {
    condition     = var.node_disk_size >= 20
    error_message = "node_disk_size must be at least 20 GiB."
  }
}
