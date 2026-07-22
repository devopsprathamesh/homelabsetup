output "velero_bucket_name" {
  value = module.backup_bucket.bucket_name
}

output "backup_kms_key_arn" {
  value = module.backup_kms.key_arn
}
