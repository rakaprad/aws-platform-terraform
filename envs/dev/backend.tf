# Partial configuration: bucket and region are supplied at init time so no
# account-specific value is committed.
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # S3 native locking (lock object next to the state); no DynamoDB table
  }
}
