####
# WAF ALLOWED IPS ONLY
# THESE ARE ALLOWED TO HIT THE ALB DIRECTLY also the BASTION HOST
####

# these are IPs are allowed via WAF and ALB directly
# on 80 (redirect to ssl) and 443
variable "allowed_ips" {
  type = list(string)
  default = [
    "82.31.227.174/32", # My IP
  ]
}