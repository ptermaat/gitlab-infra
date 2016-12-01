## EC2

### Network & Routing

# Create a VPC to launch our instances into
resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "gitlab"
    Owner = "${var.tag_Owner}"
  }
}

# Create a subnet to launch our instances into
resource "aws_subnet" "main" {
  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "10.10.1.0/24"
  availability_zone = "${var.aws_region}a"
  # TODO: comment this out once debugging is done
  map_public_ip_on_launch = true
  tags = {
    Name = "gitlab-main-subnet"
    Owner = "${var.tag_Owner}"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "gw" {
  vpc_id     = "${aws_vpc.main.id}"
  depends_on = ["aws_subnet.main"]
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
  depends_on             = ["aws_internet_gateway.gw"]
}

# Private Hosted zone for main Gitlab vpc
resource "aws_route53_zone" "private" {
   name = "honestbee.com"
   comment = "Private hosted zone for gitlab"
   vpc_id = "${aws_vpc.main.id}"
   tags = {
    Name = "honestbee-private"
    Owner = "${var.tag_Owner}"
  }
}

# Internal DNS Record for web
resource "aws_route53_record" "gitlab_web" {
   zone_id = "${aws_route53_zone.private.zone_id}"
   name = "gitlab.honestbee.com"
   type = "CNAME"
   ttl = "300"
   records = ["${aws_elb.gitlab-internal-elb.dns_name}"]
}

# Internal DNS Record for registry
resource "aws_route53_record" "gitlab_registry" {
   zone_id = "${aws_route53_zone.private.zone_id}"
   name = "glr.honestbee.com"
   type = "CNAME"
   ttl = "300"
   records = ["${aws_elb.gitlab-internal-elb.dns_name}"]
}

### Compute

#### Gitlab Host

data "template_file" "gitlab_cloudconfig" {
  template = "${file("files/gitlab/cloud-config.tpl")}"

  vars {
    aws_region              = "${var.aws_region}"
    external_url            = "${var.external_url}"
    registry_external_url   = "${var.registry_external_url}"
    gitlab_root_password    = "${var.gitlab_root_password}"
    bucket_name_registry    = "${var.bucket_name_registry}"
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
data "template_cloudinit_config" "gitlab" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = "${data.template_file.gitlab_cloudconfig.rendered}"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "${file("files/gitlab/script.deb.sh")}"
  }
}

resource "aws_instance" "gitlab_host" {
  instance_type = "${var.instance_size}"
  user_data     = "${data.template_cloudinit_config.gitlab.rendered}"
  ami           = "${data.aws_ami.ubuntu.id}"
  # The name of our SSH keypair
  key_name      = "${var.host_key_name}"
  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.gitlab_host_SG.id}"]

  subnet_id = "${aws_subnet.main.id}"
  # associate_public_ip_address = false
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
  vpc_id      = "${aws_vpc.main.id}"

  # SSH access from Public IPs and this SG
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
    cidr_blocks = ["${aws_vpc.main.cidr_block}"]
    self        = true
  }
  # HTTPS access from Internal IPs and this SG
  # ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["${aws_vpc.main.cidr_block}"]
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

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = ["${aws_security_group.gitlab_internal_ELB.id}"]
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

#### Gitlab runner

data "template_file" "gitlab_runner_cloudconfig" {
  template = "${file("files/gitlab-runner/cloud-config.tpl")}"

  vars {
    external_url            = "${var.external_url}"
    aws_region              = "${var.aws_region}"
    vpc_id                  = "${aws_vpc.main.id}"
    subnet_id               = "${aws_subnet.main.id}"
    machine_instance_size   = "${var.instance_size_builder}"
    s3_bucket               = "${var.bucket_name_cache}"
  }
}

# Render a multi-part cloudinit config
data "template_cloudinit_config" "gitlab_runner" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = "${data.template_file.gitlab_runner_cloudconfig.rendered}"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "${file("files/gitlab-runner/script.deb.sh")}"
  }
}

resource "aws_instance" "gitlab_runner" {
  instance_type = "${var.instance_size_runner}"
  user_data     = "${data.template_cloudinit_config.gitlab_runner.rendered}"
  ami           = "${data.aws_ami.ubuntu.id}"
  # The name of our SSH keypair
  key_name      = "${var.host_key_name}"
  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.gitlab_host_SG.id}"]

  subnet_id = "${aws_subnet.main.id}"
  # associate_public_ip_address = false
  # set the relevant tags
  tags = {
    Name = "gitlab_runner"
    Owner = "${var.tag_Owner}"
  }
}

#### ELB

# Separate SG for ELB
resource "aws_security_group" "gitlab_ELB_SG" {
  name        = "gitlab_ELB_SG"
  description = "Rules for Gitlab ELB"
  vpc_id      = "${aws_vpc.main.id}"

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
  subnets = ["${aws_subnet.main.id}"]
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

# Separate SG for internal ELB
resource "aws_security_group" "gitlab_internal_ELB" {
  name        = "gitlab_internal_ELB"
  description = "Rules for internal Gitlab ELB"
  vpc_id      = "${aws_vpc.main.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTPS access from the whitelist
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # SSH access from the whitelist
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # outbound access to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a new internal facing ELB to point at the instance
resource "aws_elb" "gitlab-internal-elb" {
  name = "gitlab-internal-elb"
  subnets = ["${aws_subnet.main.id}"]

  security_groups = ["${aws_security_group.gitlab_internal_ELB.id}"]

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
    Name = "gitlab_internal_elb"
    Owner = "${var.tag_Owner}"
  }
}

# S3 bucket to store our ELB access logs
# see http://docs.aws.amazon.com/ElasticLoadBalancing/latest/DeveloperGuide/enable-access-logs.html
resource "aws_s3_bucket" "gitlab" {
    bucket = "${var.bucket_name}"
    acl = "private"
    policy = "${file("bucket_policy.json")}"
    tags {
      Owner = "${var.tag_Owner}"
    }
}

# S3 bucket to store our registry images
resource "aws_s3_bucket" "registry_bucket" {
    bucket = "${var.bucket_name_registry}"
    acl = "private"
    tags {
      Owner = "${var.tag_Owner}"
    }
}

# S3 bucket to store our registry images
resource "aws_s3_bucket" "cache_bucket" {
    bucket = "${var.bucket_name_cache}"
    acl = "private"
    tags {
      Owner = "${var.tag_Owner}"
    }
}
