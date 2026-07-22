output "primary_health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "record_fqdn" {
  value = var.record_name
}
