output "bucket_name" {
  description = "S3 bucket name to reference in downstream backend.tf files."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  value = aws_s3_bucket.state.arn
}
