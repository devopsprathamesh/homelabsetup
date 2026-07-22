# DNS-level traffic control across regions. Supports two modes:
#   - "failover": PRIMARY/SECONDARY records + a health check on the primary region's
#     ingress. Used for active-passive DR (docs/dr-ha/02-multi-region-active-passive-dr.md).
#   - "latency": latency-based routing across two always-on regional endpoints. Used for
#     active-active (docs/dr-ha/03-multi-region-active-active-dr.md).
#
# This module is applied ONCE from terraform/live/global, after both regions' ingress
# load balancers exist — it reads their DNS names via variables, not remote state, to
# keep the dependency explicit and avoid a circular module graph.

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_endpoint
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 10

  # CloudWatch alarm-backed health checks catch application-level failure (5xx rate),
  # not just TCP/TLS reachability — see docs/runbooks/dr-failover-runbook.md for the
  # alarm this should be paired with.
  tags = var.tags
}

resource "aws_route53_record" "primary" {
  count = var.mode == "failover" ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  set_identifier  = "${var.primary_region}-primary"
  health_check_id = aws_route53_health_check.primary.id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = var.primary_endpoint
    zone_id                = var.primary_endpoint_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count = var.mode == "failover" ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  set_identifier = "${var.secondary_region}-secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_endpoint
    zone_id                = var.secondary_endpoint_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "latency_primary" {
  count = var.mode == "latency" ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  set_identifier = "${var.primary_region}-latency"

  latency_routing_policy {
    region = var.primary_region
  }

  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary_endpoint
    zone_id                = var.primary_endpoint_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "latency_secondary" {
  count = var.mode == "latency" ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "A"

  set_identifier = "${var.secondary_region}-latency"

  latency_routing_policy {
    region = var.secondary_region
  }

  health_check_id = aws_route53_health_check.secondary[0].id

  alias {
    name                   = var.secondary_endpoint
    zone_id                = var.secondary_endpoint_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_health_check" "secondary" {
  count = var.mode == "latency" ? 1 : 0

  fqdn              = var.secondary_endpoint
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 10

  tags = var.tags
}
