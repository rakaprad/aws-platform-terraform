# ecr

One ECR repository for application images.

Creates:

- A repository with **scan on push** (basic scanning) and **KMS encryption** (the AWS-managed `aws/ecr` key, or a customer-managed key via `kms_key_arn`)
- **Tag immutability** when `immutable_tags = true` (prod): `v1.2.3` always points to the same image digest
- A **lifecycle policy**: untagged images expire after `untagged_expiry_days`, and only the newest `keep_last_images` images are kept

## Usage

```hcl
module "ecr" {
  source = "../../modules/ecr"

  name             = "platform-prod/app"
  immutable_tags   = true
  keep_last_images = 30
}
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name` | Repository name | required |
| `immutable_tags` | Reject tag overwrites | `true` |
| `kms_key_arn` | Customer-managed KMS key, `null` = `aws/ecr` | `null` |
| `force_delete` | Delete even if images exist | `false` |
| `keep_last_images` | Images to keep | `30` |
| `untagged_expiry_days` | Expire untagged images after | `7` |

## Outputs

`repository_name`, `repository_arn`, `repository_url`.
