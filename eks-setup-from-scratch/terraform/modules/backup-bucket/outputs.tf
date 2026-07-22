output "bucket_name" {
  value = aws_s3_bucket.velero.id
}

output "bucket_arn" {
  value = aws_s3_bucket.velero.arn
}
