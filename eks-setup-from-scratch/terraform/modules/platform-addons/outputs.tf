output "aws_load_balancer_controller_role_arn" {
  value = module.addons.aws_load_balancer_controller_iam_role_arn
}

output "external_dns_role_arn" {
  value = module.addons.external_dns_iam_role_arn
}
