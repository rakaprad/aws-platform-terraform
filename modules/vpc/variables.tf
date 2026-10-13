variable "name" {
  description = "Name prefix for every resource in the module (e.g. platform-dev)."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block. Public subnets get /24s and private subnets /19s when this is a /16."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) >= 16 && tonumber(split("/", var.cidr)[1]) <= 20
    error_message = "cidr must be a valid IPv4 CIDR between /16 and /20."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (EKS needs subnets in at least two AZs)."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway shared by all AZs (cheaper, dev). false = one NAT gateway per AZ (no cross-AZ dependency, prod)."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs (ALL traffic) to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention for the flow log group, in days."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a value CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}
