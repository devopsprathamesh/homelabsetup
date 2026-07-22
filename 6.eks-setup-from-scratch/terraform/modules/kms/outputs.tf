output "key_id" {
  value = local.key_id
}

output "key_arn" {
  value = local.key_arn
}

output "alias_name" {
  value = aws_kms_alias.this.name
}
