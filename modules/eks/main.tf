data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # Add-ons the nodes need before they can become Ready (networking + Pod
  # Identity). CoreDNS is a Deployment, so it is installed after the node group.
  addons_before_nodes = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])
}

# ---------------------------------------------------------------------------
# KMS key: envelope encryption of Kubernetes Secrets + control-plane log group
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy: "*" means "this key", and the root principal delegates to IAM (AWS default key policy)
  #checkov:skip=CKV_AWS_111:Same as above: resource "*" in a key policy refers only to this key
  #checkov:skip=CKV_AWS_356:Same as above

  # Standard key policy: the account (via IAM policies) administers the key.
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # CloudWatch Logs may use the key, but only for this cluster's log group.
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:/aws/eks/${var.name}/cluster"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "EKS ${var.name}: Kubernetes secrets and control-plane logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-eks"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------
# Control-plane logs. Created before the cluster so EKS doesn't create it
# itself with infinite retention.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cluster" {
  #checkov:skip=CKV_AWS_338:Retention is a per-environment cost decision (var.log_retention_days), not a fixed 1 year

  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

# ---------------------------------------------------------------------------
# Cluster IAM role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  #checkov:skip=CKV_AWS_37:Log types are per environment (var.enabled_log_types): all five in prod, api/audit/authenticator in dev to save cost
  #checkov:skip=CKV_AWS_339:Checkov's version list lags EKS releases; the version is a variable checked against the EKS release calendar (see README)
  #checkov:skip=CKV_AWS_39:Public endpoint is off unless public_access_cidrs is set, and then restricted to those CIDRs (0.0.0.0/0 is rejected by validation)
  #checkov:skip=CKV_AWS_38:Same as above: public access is limited to var.public_access_cidrs

  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Install vpc-cni / kube-proxy / CoreDNS as managed add-ons below instead of
  # the unmanaged copies EKS would otherwise create.
  bootstrap_self_managed_addons = false

  deletion_protection       = var.deletion_protection
  enabled_cluster_log_types = var.enabled_log_types

  access_config {
    # Access entries only: no aws-auth ConfigMap.
    authentication_mode = "API"
    # Nobody gets implicit admin for having created the cluster: admins are
    # listed explicitly in var.access_entries.
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = length(var.public_access_cidrs) > 0
    public_access_cidrs     = length(var.public_access_cidrs) > 0 ? var.public_access_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = aws_kms_key.this.arn
    }
  }

  # STANDARD avoids the extended-support surcharge on old Kubernetes versions:
  # it forces you to keep upgrading instead.
  upgrade_policy {
    support_type = var.support_type
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---------------------------------------------------------------------------
# Access entries (EKS API authentication mode)
# ---------------------------------------------------------------------------
resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.this[each.key].principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/${each.value.policy}"

  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }
}

# ---------------------------------------------------------------------------
# Managed node group
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly",
    # The VPC CNI uses the node role. Moving it to its own Pod Identity role is on the roadmap.
    "AmazonEKS_CNI_Policy",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.value}"
}

resource "aws_launch_template" "node" {
  name_prefix            = "${var.name}-node-"
  update_default_version = true

  # IMDSv2 only, and a hop limit of 1 so pods (one network hop away) cannot read
  # the node role's credentials from instance metadata. Pods use Pod Identity.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-node" }
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # Let a cluster autoscaler / Karpenter change desired_size without Terraform
  # scaling it back on the next apply.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_nodes,
  ]
}

# ---------------------------------------------------------------------------
# Core add-ons (EKS picks the default version for the cluster's Kubernetes version)
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "before_nodes" {
  for_each = local.addons_before_nodes

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}
