terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap uses local state on purpose: the bucket it creates is where every
  # other state file lives. Keep bootstrap/terraform.tfstate safe, or migrate it
  # into the new bucket afterwards (see README).
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "aws-platform-terraform"
      ManagedBy = "terraform"
      Purpose   = "terraform-state"
    }
  }
}
