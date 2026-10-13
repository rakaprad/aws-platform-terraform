# budget

A monthly AWS cost budget with email alerts.

Creates one `aws_budgets_budget` (type `COST`, USD, monthly) with:

- An email alert for each percentage in `alert_thresholds`, based on **actual** spend
- One extra alert when the **forecast** for the month goes over 100%

The budget covers the **whole account**. That's one reason to give each environment its own AWS account. The environments create it only when `budget_alert_emails` is set.

## Usage

```hcl
module "budget" {
  source = "../../modules/budget"

  name         = "platform-dev-monthly"
  limit_amount = 250
  alert_emails = ["you@example.com"]
}
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name` | Budget name | required |
| `limit_amount` | Monthly limit, USD | required |
| `alert_thresholds` | Percentages for actual-spend alerts | `[50, 80, 100]` |
| `alert_emails` | 1-10 recipients | required |

## Outputs

`budget_name`.
