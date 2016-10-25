output "elb_dns" {
    value = "${aws_elb.gitlab-elb.dns_name}"
}

output "host_ip" {
    value = "${aws_instance.gitlab_host.public_ip}"
}

