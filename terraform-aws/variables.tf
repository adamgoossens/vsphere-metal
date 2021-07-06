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

variable "fedora_amis" {
  type = map
  default = {
    "us-east-1" = "ami-09e08e82e8f927ba4"
    "us-east-2" = "ami-04d6c97822332a0a6"
    "us-west-1" = "ami-0d828c0715f284b51"
    "ap-southeast-1" = "ami-0de1a1ee38e9d0267"
    "ap-southeast-2" = "ami-0627bcdb0bea81d1b"
    "eu-west-2" = "ami-034794b0310a1d8b7"
  }
}
