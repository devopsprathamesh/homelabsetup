output "velero_bucket_name" {
  value = module.backup_bucket.bucket_name
}

output "backup_kms_key_arn" {
  value = module.backup_kms.key_arn
}

output "primary_health_check_id" {
  description = "Only set once enable_dr_failover_dns = true. Used to check failover status: aws route53 get-health-check-status --health-check-id <this>."
  value       = var.enable_dr_failover_dns ? module.dns_failover[0].primary_health_check_id : null
}
