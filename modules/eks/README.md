# eks

An EKS cluster with one managed node group in private subnets.

Creates:

- **Cluster** with the private endpoint always on. The public endpoint is only enabled when `public_access_cidrs` is non-empty, and then only for those CIDRs (`0.0.0.0/0` is rejected by validation)
- A **KMS key** (rotation on) for envelope encryption of Kubernetes Secrets. The same key encrypts the control-plane log group
- **Control-plane logging** to a log group that Terraform creates first, so retention is set and not "never expire"
- **Access entries** (`authentication_mode = "API"`) instead of the `aws-auth` ConfigMap. `bootstrap_cluster_creator_admin_permissions = false`, so whoever ran `terraform apply` does not get hidden admin rights. Admins are listed in `access_entries`
- **Managed node group** (AL2023) using a launch template with IMDSv2 required, a **hop limit of 1** (pods can't read the node role's credentials from instance metadata) and an encrypted gp3 root volume
- **Managed add-ons**: `vpc-cni`, `kube-proxy` and `eks-pod-identity-agent` before the nodes, and `coredns` after them. `bootstrap_self_managed_addons = false` so EKS doesn't also install unmanaged copies
- `upgrade_policy.support_type = "STANDARD"` by default, to avoid the extended-support surcharge for old versions
- Optional `deletion_protection`

## Pod Identity rather than IRSA

The module installs the **EKS Pod Identity Agent** and creates no IAM OIDC provider for the cluster. Reasons:

- **No per-cluster OIDC provider** and no trust policy that hard-codes the cluster's OIDC issuer URL. A Pod Identity role trusts one service principal (`pods.eks.amazonaws.com`), so the same role can be reused across clusters and survives a cluster rebuild
- The pod-to-role mapping is an EKS API object (`aws_eks_pod_identity_association`) instead of a ServiceAccount annotation, so it is managed and audited in AWS (CloudTrail)
- Session tags (cluster name, namespace, service account) make ABAC possible

IRSA is still the better choice for workloads outside EKS (e.g. self-managed Kubernetes) or for the few add-ons that don't support Pod Identity yet.

Giving an app an IAM role:

```hcl
data "aws_iam_policy_document" "pods_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "platform-dev-app"
  assume_role_policy = data.aws_iam_policy_document.pods_assume.json
}

resource "aws_eks_pod_identity_association" "app" {
  cluster_name    = module.eks.cluster_name
  namespace       = "apps"
  service_account = "app"
  role_arn        = aws_iam_role.app.arn
}
```

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  name                = "platform-dev"
  kubernetes_version  = "1.36"
  subnet_ids          = module.vpc.private_subnet_ids
  public_access_cidrs = ["203.0.113.10/32"]
  deletion_protection = false

  access_entries = {
    admin  = { principal_arn = "arn:aws:iam::123456789012:role/Admin" }
    deploy = { principal_arn = module.github_oidc.deploy_role_arn, policy = "AmazonEKSEditPolicy", namespaces = ["apps"] }
  }
}
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name` | Cluster name and prefix for IAM roles, KMS alias, log group | required |
| `kubernetes_version` | e.g. `1.36` | required |
| `support_type` | `STANDARD` or `EXTENDED` | `STANDARD` |
| `subnet_ids` | Private subnets (2+ AZs) | required |
| `public_access_cidrs` | CIDRs for the public endpoint; empty = private only | `[]` |
| `deletion_protection` | Block cluster deletion | `true` |
| `enabled_log_types` | Control-plane log types | all five |
| `log_retention_days` | Control-plane log retention | `90` |
| `access_entries` | `map(object({ principal_arn, policy, namespaces }))` | `{}` |
| `node_instance_types`, `node_capacity_type` | Node group instances, `ON_DEMAND`/`SPOT` | `["t3.medium"]`, `ON_DEMAND` |
| `node_min_size`, `node_desired_size`, `node_max_size` | Scaling (desired is ignored after creation) | `1`, `2`, `3` |
| `node_disk_size` | Root volume, GiB | `30` |

## Outputs

`cluster_name`, `cluster_arn`, `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_security_group_id`, `node_role_arn`, `kms_key_arn`.
