# vpc

A VPC for EKS, written with plain `aws_*` resources (no community module) so every piece is visible.

Creates:

- A VPC with DNS support and hostnames, plus a default security group with **all rules removed**
- **Public subnets** (`/24` each when the VPC is a `/16`), one per AZ, tagged `kubernetes.io/role/elb=1` for internet-facing load balancers. `map_public_ip_on_launch = false`
- **Private subnets** (`/19` each) for nodes and pods, tagged `kubernetes.io/role/internal-elb=1`. They are large because the VPC CNI gives every pod a VPC IP
- An internet gateway, and NAT gateways with Elastic IPs: **one shared** (`single_nat_gateway = true`, dev) or **one per AZ** (prod)
- One private route table per AZ, so each AZ can use its own NAT gateway
- An **S3 gateway endpoint** on all route tables. It is free and keeps S3 traffic (including ECR image layers) off the NAT gateway
- Optional **VPC flow logs** (ALL traffic) to a CloudWatch log group, with a dedicated IAM role that has confused-deputy protection

Subnet layout for `10.10.0.0/16` and 3 AZs:

| Subnet | AZ a | AZ b | AZ c |
|--------|------|------|------|
| public | `10.10.0.0/24` | `10.10.1.0/24` | `10.10.2.0/24` |
| private | `10.10.32.0/19` | `10.10.64.0/19` | `10.10.96.0/19` |

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name               = "platform-dev"
  cidr               = "10.10.0.0/16"
  az_count           = 3
  single_nat_gateway = true
  enable_flow_logs   = false
}
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name` | Name prefix | required |
| `cidr` | VPC CIDR, `/16` to `/20` | `10.0.0.0/16` |
| `az_count` | AZs to use (2 or 3) | `3` |
| `single_nat_gateway` | One shared NAT gateway instead of one per AZ | `false` |
| `enable_flow_logs` | VPC flow logs to CloudWatch Logs | `true` |
| `flow_logs_retention_days` | Flow log retention | `30` |

## Outputs

`vpc_id`, `vpc_cidr`, `azs`, `public_subnet_ids`, `private_subnet_ids`, `nat_public_ips`.
