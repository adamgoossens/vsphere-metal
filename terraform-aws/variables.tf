variable "base_domain" {
  description = "The base Route53 domain to use"
  type        = string
}

variable "aws_region" {
  description = "Which AWS region to deploy into. The default is us-east-1"
  type        = string
  default     = "us-east-1"
  validation {
    condition = contains(["us-east-1", "us-east-2", "us-west-1", "ap-southeast-1", "ap-southeast-2", "eu-west-2"], var.aws_region)
    error_message = "Valid regions are us-east-1, us-east-2, us-west-1, ap-southeast-1, ap-southeast-2, eu-west-2."
  }
}

variable "equinix_gateway_public_ip" {
  description = "Public IP of Equinix gateway. Will be added to Route53"
  type = string
}
