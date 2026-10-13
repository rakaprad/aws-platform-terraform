data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  github_oidc_host = "token.actions.githubusercontent.com"
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : (
    data.aws_iam_openid_connect_provider.github[0].arn
  )

  eks_cluster_arn = "arn:${local.partition}:eks:${local.region}:${local.account_id}:cluster/${var.eks_cluster_name}"
  state_bucket    = "arn:${local.partition}:s3:::${var.state_bucket_name}"
}

# ---------------------------------------------------------------------------
# OIDC provider: one per account. If dev and prod share an account, create it
# in one environment and set create_oidc_provider = false in the other.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # No thumbprint_list: IAM validates GitHub's certificate against its own
  # trusted CA store for this provider.
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://${local.github_oidc_host}"
}

# Shared trust policy shape: a GitHub OIDC token, issued for AWS STS, whose
# `sub` claim matches one of the allowed subjects (repo + branch/environment).
data "aws_iam_policy_document" "assume" {
  for_each = {
    terraform = var.terraform_role_subjects
    deploy    = var.deploy_role_subjects
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_host}:sub"
      values   = each.value
    }
  }
}

# ---------------------------------------------------------------------------
# Deploy role: push to ONE ECR repository and look up ONE EKS cluster.
# Kubernetes permissions come from an EKS access entry (see envs/*/main.tf).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "deploy" {
  name                 = "${var.name}-github-deploy"
  description          = "GitHub Actions: push images and deploy to ${var.eks_cluster_name}"
  assume_role_policy   = data.aws_iam_policy_document.assume["deploy"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"] # does not support resource-level permissions
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "EksKubeconfig"
    actions   = ["eks:DescribeCluster"]
    resources = [local.eks_cluster_arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------------------------------------------------------------------------
# Terraform role: manage the resources in this repo, nothing else (by service,
# region and name prefix), plus read/write on this environment's state only.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "terraform" {
  name                 = "${var.name}-github-terraform"
  description          = "GitHub Actions: terraform plan/apply for ${var.name}"
  assume_role_policy   = data.aws_iam_policy_document.assume["terraform"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "terraform" {
  #checkov:skip=CKV_AWS_109:Terraform must manage KMS key policies, scoped by region; see README trade-offs
  #checkov:skip=CKV_AWS_111:Write access is scoped by service and region (and IAM by name prefix); ARNs of resources Terraform creates are not known up front
  #checkov:skip=CKV_AWS_356:Same as above: '*' is limited by service list + aws:RequestedRegion
  #checkov:skip=CKV2_AWS_40:Full-service actions on ec2/eks/ecr/kms/logs are an accepted trade-off for an IaC role; see README

  statement {
    sid = "RegionalInfrastructure"
    actions = [
      "ec2:*",
      "ecr:*",
      "eks:*",
      "kms:*",
      "logs:*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid       = "Budgets" # global service
    actions   = ["budgets:*"]
    resources = ["arn:${local.partition}:budgets::${local.account_id}:budget/*"]
  }

  statement {
    sid       = "IamRead"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid = "IamManageOwnRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${var.name}-*"]
  }

  statement {
    sid = "IamGithubOidcProvider"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.github_oidc_host}"]
  }

  statement {
    sid       = "PassOwnRolesToEksAndFlowLogs"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/${var.name}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "autoscaling.amazonaws.com",
        "spot.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket] # key names only; object reads are limited below
  }

  statement {
    sid       = "StateReadWrite" # state file + the .tflock lock object
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket}/${var.state_key_prefix}/*"]
  }

  # Explicit denies win over any allow, including ones added later by mistake.
  statement {
    sid    = "DenyLongLivedCredentialsAndAccountChanges"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:AddUserToGroup",
      "organizations:*",
      "account:*",
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DenyAttachingAdminPolicies"
    effect    = "Deny"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values = [
        "arn:${local.partition}:iam::aws:policy/AdministratorAccess",
        "arn:${local.partition}:iam::aws:policy/PowerUserAccess",
        "arn:${local.partition}:iam::aws:policy/IAMFullAccess",
      ]
    }
  }
}

resource "aws_iam_role_policy" "terraform" {
  name   = "terraform"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform.json
}
