locals {
  env  = "dev"
  name = "platform-${local.env}"

  app_repository = coalesce(var.app_github_repository, var.github_repository)

  # Humans who administer the cluster, plus the deploy role limited to the
  # application namespace.
  access_entries = merge(
    { for i, arn in var.cluster_admin_arns : "admin-${i}" => { principal_arn = arn } },
    {
      github-deploy = {
        principal_arn = module.github_oidc.deploy_role_arn
        policy        = "AmazonEKSEditPolicy"
        namespaces    = ["apps"]
      }
    },
  )
}

module "vpc" {
  source = "../../modules/vpc"

  name                     = local.name
  cidr                     = "10.10.0.0/16"
  az_count                 = 3
  single_nat_gateway       = true # one NAT for all AZs: saves ~2 NAT gateways, accepts an AZ dependency
  enable_flow_logs         = false
  flow_logs_retention_days = 7
}

module "eks" {
  source = "../../modules/eks"

  name                = local.name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = module.vpc.private_subnet_ids
  public_access_cidrs = var.public_access_cidrs
  deletion_protection = false
  enabled_log_types   = ["api", "audit", "authenticator"]
  log_retention_days  = 7
  access_entries      = local.access_entries

  node_instance_types = ["t3.medium"]
  node_capacity_type  = "ON_DEMAND"
  node_min_size       = 1
  node_desired_size   = 2
  node_max_size       = 3
  node_disk_size      = 30
}

module "ecr" {
  source = "../../modules/ecr"

  name             = "${local.name}/app"
  immutable_tags   = false
  force_delete     = true
  keep_last_images = 10
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  name                 = local.name
  create_oidc_provider = var.create_github_oidc_provider

  # PR plans (pull_request) and applies from the `dev` GitHub environment.
  terraform_role_subjects = [
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:environment:${local.env}",
  ]
  # The app repo's main branch may push images and deploy to dev.
  deploy_role_subjects = ["repo:${local.app_repository}:ref:refs/heads/main"]

  ecr_repository_arn = module.ecr.repository_arn
  eks_cluster_name   = local.name
  state_bucket_name  = var.state_bucket_name
  state_key_prefix   = "envs/${local.env}"
}

module "budget" {
  source = "../../modules/budget"
  count  = length(var.budget_alert_emails) > 0 ? 1 : 0

  name         = "${local.name}-monthly"
  limit_amount = var.budget_limit_usd
  alert_emails = var.budget_alert_emails
}
