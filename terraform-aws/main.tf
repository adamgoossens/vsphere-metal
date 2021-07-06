terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  region = var.aws_region
}

data "aws_route53_zone" "metal" {
  name  = "${var.base_domain}."
}

resource "aws_route53_record" "star_metal" {
  zone_id = data.aws_route53_zone.metal.zone_id
  name = "*.metal.${data.aws_route53_zone.metal.name}"
  type = "A"
  ttl = "120"
  records = [${var.equinix_gw_public_ip]
}
