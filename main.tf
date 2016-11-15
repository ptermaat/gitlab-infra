data "template_file" "cloud-config" {
  template = "${file("files/gitlab/cloud-config.tpl")}"

  vars {
    external_url            = "${var.external_url}"
    registry_external_url   = "${var.registry_external_url}"
    smtp_user               = "${var.smtp_user}"
    smtp_password           = "${var.smtp_password}"
    smtp_host               = "${var.smtp_host}"
    smtp_port               = "${var.smtp_port}"
    smtp_from_email         = "${var.smtp_from_email}"
    smtp_email_display_name = "${var.smtp_email_display_name}"
    smtp_email_reply_to     = "${var.smtp_email_reply_to}"
  }
}

# Render a multi-part cloudinit config
data "template_cloudinit_config" "config" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = "${data.template_file.cloud-config.rendered}"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "${file("files/gitlab/script.deb.sh")}"
  }
}

resource "aws_instance" "gitlab_host" {
  instance_type = "${var.instance_size}"
  user_data     = "${data.template_cloudinit_config.config.rendered}"
  ami           = "${data.aws_ami.ubuntu.id}"
  # The name of our SSH keypair
  key_name      = "${var.host_key_name}"
  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.gitlab_host_SG.id}"]

  subnet_id = "${var.host_subnet}"
  associate_public_ip_address = false
  # set the relevant tags
  tags = {
    Name = "gitlab_host"
    Owner = "${var.tag_Owner}"
  }
}

# host security group, no external access - that will be on the ELB SG
resource "aws_security_group" "gitlab_host_SG" {
  name        = "gitlab_host"
  description = "Rules for Gitlab host access"
  vpc_id      = "${var.account_vpc}"

  # SSH access from Internal IPs and this SG
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    self = true
  }
  # HTTP access from VPC and this SG
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
    self        = true
  }
  # HTTPS access from Internal IPs and this SG
  # ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["172.31.0.0/16"]
  #   self        = true
  # }
  # next few rules allow access from the ELB SG
  # can't mix CIDR and SGs, so repeating a lot of the above

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = ["${aws_security_group.gitlab_ELB_SG.id}"]
  }
  # ingress {
  #   from_port = 443
  #   to_port = 443
  #   protocol = "tcp"
  #   security_groups = ["${aws_security_group.gitlab_ELB_SG.id}"]
  # }
  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Separate SG for ELB
resource "aws_security_group" "gitlab_ELB_SG" {
  name        = "gitlab_ELB_SG"
  description = "Rules for Gitlab ELB"
  vpc_id      = "${var.account_vpc}"

  # HTTP access from our whitelist
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${split(",", var.elb_whitelist)}"]
  }
  # HTTPS access from the whitelist
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${split(",", var.elb_whitelist)}"]
  }
  # SSH access from the whitelist
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${split(",", var.elb_whitelist)}"]
  }
  # outbound access to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a new external facing ELB to point at the instance
resource "aws_elb" "gitlab-elb" {
  name = "gitlab-elb"
  subnets = ["${var.elb_subnet}"]
  #
  security_groups = ["${aws_security_group.gitlab_ELB_SG.id}"]
  # this requires a valid bucket policy for the ELB to write to the bucket
  # http://docs.aws.amazon.com/ElasticLoadBalancing/latest/DeveloperGuide/enable-access-logs.html#attach-bucket-policy
  access_logs {
    bucket = "${var.bucket_name}"
    bucket_prefix = "ELBAccessLogs"
    interval = 60
  }
  # Listen on HTTP
  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }
  # Listen on SSL
  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 443
    lb_protocol = "https"
    ssl_certificate_id = "${var.elb_ssl_cert}"
  }

  # Listen on SSH (git push)
  listener {
    instance_port = 22
    instance_protocol = "tcp"
    lb_port = 22
    lb_protocol = "tcp"
  }


  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/explore"
    interval = 30
  }

  instances = ["${aws_instance.gitlab_host.id}"]
  cross_zone_load_balancing = true
  idle_timeout = 400
  connection_draining = true
  connection_draining_timeout = 400

  tags {
    Name = "gitlab_elb"
    Owner = "${var.tag_Owner}"
  }
}

# now an S3 bucket to store our ELB access logs
# see http://docs.aws.amazon.com/ElasticLoadBalancing/latest/DeveloperGuide/enable-access-logs.html
resource "aws_s3_bucket" "gitlab" {
    bucket = "${var.bucket_name}"
    acl = "private"
    policy = "${file("bucket_policy.json")}"
    tags {
      Owner = "${var.tag_Owner}"
    }
}
