#######################################
## waf
########################################
# ips ipset
resource "aws_wafv2_ip_set" "waf_allowed_ip" {
  provider = aws.eu-west-2_static

  name               = "${var.name}-allowed-internal-ip"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ips
}

resource "aws_wafv2_web_acl" "waf" {
  #checkov:skip=CKV_AWS_192: "Ensure WAF prevents message lookup in Log4j2. See CVE-2021-44228 aka log4jshell"
  provider = aws.eu-west-2_static

  name  = "${var.name}-waf"
  scope = "CLOUDFRONT"

  default_action {
    block {} # block all requests by default. see rules for allow
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "waf-${var.name}-waf"
    sampled_requests_enabled   = true
  }

  # aws managed rules https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      none {} # use action defined in aws managed rule
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "waf-aws-managed-rule-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesUnixRuleSet"
    priority = 2

    override_action {
      none {} # use action defined in aws managed rule
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesUnixRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "waf-aws-managed-rule-posix-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {} # use action defined in aws managed rule
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "waf-aws-managed-rule-sqli-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AllowInternalIPs"
    priority = 4

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.waf_allowed_ip.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "waf-allow-internal-ips"
      sampled_requests_enabled   = true
    }
  }
  }

  dynamic "rule" {
    # create this rule only if the length of the var var.waf_geo_restriction_locations is 1 or more, ie: a location is set
    for_each = length(var.waf_allow_geo_locations) >= 1 ? [1] : []

    content {
      name     = "AllowGeos"
      priority = 6

      action {
        allow {}
      }

      statement {
        geo_match_statement {
          country_codes = var.waf_allow_geo_locations
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = false
        metric_name                = "waf-aws-allow-geos"
        sampled_requests_enabled   = true
      }
    }
  }

  lifecycle {
    # There is an issue with the provider when adding a new tag to WAF. Error: Provider produced inconsistent final plan
    # Add new tags manually to WAF if needed.
    ignore_changes = [tags_all]
  }
}

resource "aws_cloudwatch_log_group" "waf_cloudwatch_lg" {
  #checkov:skip=CKV_AWS_158: "Ensure that CloudWatch Log Group is encrypted by KMS"
  provider = aws.eu-west-2_static

  name              = "aws-waf-logs-waf/${aws_wafv2_web_acl.waf.name}"
  kms_key_id        = var.aws_region == "us-east-1" ? aws_kms_key.cloudwatch_kms.arn : aws_kms_key.us_east_1_cloudwatch_kms[0].arn
  retention_in_days = var.environment == "prod" ? var.ecs_cloudwatch_log_retention_days : floor(var.ecs_cloudwatch_log_retention_days / 3)
}

resource "aws_wafv2_web_acl_logging_configuration" "waf_logging_configuration" {
  provider = aws.eu-west-2_static

  log_destination_configs = [aws_cloudwatch_log_group.waf_cloudwatch_lg.arn]
  resource_arn            = aws_wafv2_web_acl.waf.arn
}