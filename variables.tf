#
# General variables file
#
# Variables need to be defined even though they are loaded from
# terraform.tfvars - see https://github.com/hashicorp/terraform/issues/2659

# Ubuntu 16.04 LTS AMIs (HVM:instancestore) will be used

variable "amazon_amis" {
  default = {
    ap-northeast-1 = "ami-839b3de2"
    ap-southeast-1 = "ami-7a288e19"
    ap-southeast-2 = "ami-dc3a07bf"
    cn-north-1 = "ami-5af22637"
    eu-central-1 = "ami-1279807d"
    eu-west-1 = "ami-d17836a2"
    sa-east-1 = "ami-d439a4b8"
    us-east-1 = "ami-3fabf828"
    us-gov-west-1 = "ami-69d66e08"
    us-west-1 = "ami-ff175c9f"
    us-west-2 = "ami-fbd5719b"
  }
}

variable "tag_Owner" {
    default = "owner@example.com"
}

variable "aws_region" {
    default = "us-west-2"
}

variable "account_vpc" {
    default = "vpc-11111111"
}
variable "host_key_name" {
    default = "host_keypair"
}
variable "private_key_path" {
    default = "~/.ssh/keypair.pem"
}
variable "instance_size" {
    default = "m3.medium"
}
variable "elb_ssl_cert" {
    default = "arn:aws:iam::111111111111:server-certificate/gitlab.example.com"
}
variable "host_subnet" {
    default = "subnet-FFFFFFFF"
}
variable "bucket_name" {
    default = "mybucket"
}
variable "elb_subnet" {
    default = "subnet-EEEEEEEE"
}
variable "elb_whitelist" {
    default = "198.51.100.0/24,203.0.113.0/24"
}
