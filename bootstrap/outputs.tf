output "state_bucket_name" {
  description = "Use as `bucket` in envs/*/backend.hcl and as the TF_STATE_BUCKET GitHub variable."
  value       = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_region" {
  description = "Use as `region` in envs/*/backend.hcl."
  value       = var.region
}
