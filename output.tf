output "elb_dns" {
    value = "${aws_elb.gitlab-elb.dns_name}"
}

output "vpc_id" {
    value = "${aws_vpc.main.id}"
}

output "gitlab_ip" {
    value = "${aws_instance.gitlab_host.public_ip}"
}

output "gitlab_runner_ip" {
    value = "${aws_instance.gitlab_runner.public_ip}"
}
