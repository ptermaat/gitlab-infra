#
# General variables file
#
# Variables need to be defined even though they are loaded from
# terraform.tfvars - see https://github.com/hashicorp/terraform/issues/2659

# Ubuntu 16.04 LTS AMIs (HVM:ebs) will be used
# aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=*hvm*ssd*-16.04*"
# http://docs.aws.amazon.com/cli/latest/reference/ec2/describe-images.html
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["*hvm-ssd*-16.04*"]
  }

  owners = ["099720109477"] # Canonical
}

variable "tag_Owner" {
    default = "owner@example.com"
}

variable "aws_region" {
    default = "us-west-2"
}

variable "host_key_name" {
    default = "host_keypair"
}
variable "private_key_path" {
    default = "~/.ssh/keypair.pem"
}
# GitLab host
variable "instance_size" {
    default = "m4.medium"
}
# Runner scheduling jobs and managing builders
variable "instance_size_runner" {
    default = "t2.medium"
}
# Size of instances provisioned by the runner
variable "instance_size_builder" {
    default = "c3.large"
}
variable "elb_ssl_cert" {
    default = "arn:aws:iam::111111111111:server-certificate/gitlab.example.com"
}
variable "bucket_name" {
    default = "mybucket"
}
variable "bucket_name_registry" {
    default = "myregistrybucket"
}
variable "bucket_name_cache" {
    default = "mycachebucket"
}
variable "elb_whitelist" {
    default = "198.51.100.0/24,203.0.113.0/24"
}
variable "external_url" {
    default = "https://gitlab.example.com"
}
variable "registry_external_url" {
    default =  "https://registry.example.com"
}
variable "gitlab_root_password" {
    default = "5iveL!fe"
}
variable "smtp_user" {
    default =  "admin@example.com"
}
variable "smtp_password" {
    default =  "mysupersecret"
}
variable "smtp_host" {
    default =  "smtp.mandrillapp.com"
}
variable "smtp_port" {
    default =  587
}
variable "smtp_from_email" {
    default =  "gitlab@example.com"
}
variable "smtp_email_display_name" {
    default =  "Example Gitlab"
}
variable "smtp_email_reply_to" {
    default =  "noreply@example.com"
}
