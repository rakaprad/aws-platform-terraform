terraform {
  # >= 1.10 for S3 native state locking (use_lockfile).
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Refuse to run against any other account (e.g. prod credentials in a dev shell).
  allowed_account_ids = [var.account_id]

  # Applied to every resource that supports tags.
  default_tags {
    tags = {
      Project     = "aws-platform-terraform"
      Environment = local.env
      ManagedBy   = "terraform"
    }
  }
}
