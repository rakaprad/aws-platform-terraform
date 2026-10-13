variable "name" {
  description = "Budget name."
  type        = string
}

variable "limit_amount" {
  description = "Monthly budget in USD. Covers the whole account, so use one account per environment for per-environment budgets."
  type        = number

  validation {
    condition     = var.limit_amount > 0
    error_message = "limit_amount must be greater than 0."
  }
}

variable "alert_thresholds" {
  description = "Percentages of the budget (actual spend) that trigger an email."
  type        = list(number)
  default     = [50, 80, 100]

  validation {
    condition     = alltrue([for t in var.alert_thresholds : t > 0 && t <= 1000])
    error_message = "Thresholds must be percentages between 0 and 1000."
  }
}

variable "alert_emails" {
  description = "Email addresses notified at each threshold (max 10 per notification)."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0 && length(var.alert_emails) <= 10 && alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alert_emails must contain 1-10 valid email addresses."
  }
}
