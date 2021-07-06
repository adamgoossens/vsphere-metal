output "gw_fqdn" {
  value   = aws_eip.metal_gw.public_dns
  description = "FQDN for the gateway in AWS"
}
