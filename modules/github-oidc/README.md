# github-oidc

Keyless GitHub Actions → AWS authentication through **IAM OIDC federation**. No access keys are created anywhere.

Creates:

- The IAM **OIDC provider** for `https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com`. Only one can exist per account, so set `create_oidc_provider = false` in the second environment if dev and prod share an account. The module then looks the existing one up
- Two roles. Their trust policies only accept a GitHub token whose `aud` is `sts.amazonaws.com` **and** whose `sub` matches an allowed subject, for example:
  - `repo:rakaprad/aws-platform-terraform:pull_request` (PR plans)
  - `repo:rakaprad/aws-platform-terraform:environment:prod` (jobs running in the protected `prod` environment)
  - `repo:rakaprad/my-app:ref:refs/heads/main` (the app's main branch)

  Validation rejects subjects with a wildcard in the owner or repository name.
- **Deploy role** (`<name>-github-deploy`) for application pipelines:
  - `ecr:GetAuthorizationToken` (it has no resource-level permissions) and push/pull on **one repository**
  - `eks:DescribeCluster` on **one cluster**, enough for `aws eks update-kubeconfig`
  - Kubernetes rights come from an EKS access entry, not IAM. The envs give it `AmazonEKSEditPolicy` in the `apps` namespace only
- **Terraform role** (`<name>-github-terraform`) for this repo's workflow:
  - `ec2:*`, `eks:*`, `ecr:*`, `kms:*`, `logs:*`, **only in the configured region** (`aws:RequestedRegion`)
  - `budgets:*` on this account's budgets
  - IAM: read everything, write only roles named `<name>-*` and the GitHub OIDC provider. `iam:PassRole` only for `<name>-*` roles, and only to EKS and VPC Flow Logs. Service-linked roles only for EKS, node groups, Auto Scaling and Spot
  - State: read/write on `s3://<state bucket>/<state_key_prefix>/*` only, so the dev role can't touch prod state
  - **Explicit denies**: creating IAM users, access keys or console passwords; any `organizations:*` or `account:*` action; stopping or changing CloudTrail; attaching `AdministratorAccess`, `PowerUserAccess` or `IAMFullAccess` to any role

## Trade-offs (Terraform role)

- An IaC role that can write IAM roles can, in principle, create a role with more power than itself and assume it. The name prefix, the PassRole conditions and the explicit denies make that harder, but they don't make it impossible. In practice, **whoever can get a workflow to run with this role is close to an admin of the account.** The real controls are therefore on the GitHub side: the `sub` condition, branch protection, and required reviewers on the `prod` environment. Separate AWS accounts per environment limit the blast radius
- Service-wide actions (`ec2:*` and so on) are used because the ARNs Terraform creates aren't known in advance. Narrowing them further usually breaks the next `apply`. They are limited to one region
- PR plans use the same role as applies. A same-repo PR author could change the workflow to run `apply` with it. Fork PRs never get a token. A read-only plan role is on the roadmap

## Usage

```hcl
module "github_oidc" {
  source = "../../modules/github-oidc"

  name = "platform-dev"
  terraform_role_subjects = [
    "repo:rakaprad/aws-platform-terraform:pull_request",
    "repo:rakaprad/aws-platform-terraform:environment:dev",
  ]
  deploy_role_subjects = ["repo:rakaprad/my-app:ref:refs/heads/main"]

  ecr_repository_arn = module.ecr.repository_arn
  eks_cluster_name   = "platform-dev"
  state_bucket_name  = "123456789012-tfstate-ap-southeast-3"
  state_key_prefix   = "envs/dev"
}
```

In a workflow:

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v6
    with:
      role-to-assume: ${{ vars.DEV_TF_ROLE_ARN }}   # output terraform_role_arn
      aws-region: ap-southeast-3
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name` | Prefix for role names and the IAM scope of the Terraform role | required |
| `create_oidc_provider` | Create the account-wide provider (or look it up) | `true` |
| `terraform_role_subjects`, `deploy_role_subjects` | Allowed `sub` claims | required |
| `ecr_repository_arn` | Repository the deploy role can push to | required |
| `eks_cluster_name` | Cluster the deploy role can describe | required |
| `state_bucket_name`, `state_key_prefix` | State the Terraform role can read and write | required |

## Outputs

`oidc_provider_arn`, `terraform_role_arn`, `deploy_role_arn`.
