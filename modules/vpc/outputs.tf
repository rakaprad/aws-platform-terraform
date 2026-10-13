output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones used, in subnet order."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT gateways, internet-facing load balancers)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes and pods, internal load balancers)."
  value       = aws_subnet.private[*].id
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateways: the egress IPs to allow-list in third-party services."
  value       = aws_eip.nat[*].public_ip
}
