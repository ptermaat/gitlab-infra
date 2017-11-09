# tf-aws-gitlab

Terraform config to create a Gitlab host and Gitlab Multi Runner using Ubuntu 16.04 LTS and Omnibus Gitlab package.

Tested with Gitlab 8.14 and Gitlab-runner 1.8.

This will create a dedicated VPC, a Private Hosted DNS Zone as well as Public and private ELBs for TLS termination using AWS Certificate Management.

All actual values have been generalized, or gitignored.

## Steps to provision

1. Prepare terraform.tfvars file:
   ```
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars
   ```

   Existing AWS Resources
   ```
   # List existing TLS Certs
   aws iam list-server-certificates --query "ServerCertificateMetadataList[].[ServerCertificateName,Arn]" --output=table
   # Add your ip to white list:
   curl ifconfig.co
   ```

   You may need to decrypt your private key for Terraform to use it:
   ```
   openssl rsa -in ~/.ssh/id_rsa  -out ~/.ssh/id_rsa-decrypted
   ```

1. set environment variables
   ```
   export TF_VAR_aws_access_key=AKIA...
   export TF_VAR_aws_secret_key=x823dzzawer...
   ```

1. Edit `bucket_policy.json`, follow [AWS steps](http://docs.aws.amazon.com/ElasticLoadBalancing/latest/DeveloperGuide/enable-access-logs.html#attach-bucket-policy)
   update principal and account id:
   ```
   # Get 12 Digit Acount ID
   aws iam get-user --output text --query='User.Arn' | grep -Eo '[[:digit:]]{12}'
   ```


1. Create stack:

   ```
   terraform plan
   ```

   ```
   terraform apply
   ```

   Output should provide name of provisioned ELB. Create Route53 CNAME records matching `external_url` and `registry_external_url`.

   ```
   terraform output elb_dns | pbcopy
   aws route53 list-hosted-zones-by-name --query "HostedZones[].[Name,Id,Config.Comment,Config.PrivateZone]" --output table
   aws route53 list-resource-record-sets --hosted-zone-id <zone-id> \
     --query "ResourceRecordSets[?Type != 'TXT'].[Type,Name,AliasTarget.DNSName || ResourceRecords[0].Value]"  --output table
   ```

1. Wait for Gitlab instance to report as Healthy and register with ELB:

   ```
   while true;do aws elb describe-instance-health --load-balancer-name gitlab-elb --query "InstanceStates[].State" --output=text;sleep 1; done
   ```

1. Do Gitlab configuration

   ```
   pbcopy < ~/.ssh/rsa_id.pub
   ```

   ```
   open http://gitlab.example.com
   ```

   1. Log in with username `root` and password `gitlab_root_password`
   1. Log out and test registration.
   2. Add public key

Note: If you need to change ssh key:
```
ssh-keygen -R "gitlab.example.com"
ssh-keygen -R "glr.example.com"
```

## Registering Multi Runner:

Current Cloud-Config will stop gitlab runner after everything is installed.

Note Runner registration token:

```
ssh ubuntu@$(terraform output gitlab_ip) "sudo gitlab-rails runner 'puts ApplicationSetting.current.runners_registration_token'"
```

Log in to runner:
```
ssh ubuntu@$(terraform output gitlab_runner_ip)
```

Register runner instance with GitlabCI [using API](http://docs.gitlab.com/ce/api/ci/runners.html):
```
sudo -i
gitlab-runner stop
export AWS_ACCESS_KEY_ID=AKI.................
export AWS_SECRET_ACCESS_KEY=8T......................................
export REGISTRATION_TOKEN=ZRvbzXdYBiWX6kUp1Ytz
export RUNNER_TOKEN=$(curl -sXPOST "https://gitlab.example.com/ci/api/v1/runners/register" --form "token=$REGISTRATION_TOKEN" | jq -r .token)

sed -i "s/ADD-TOKEN-HERE/$RUNNER_TOKEN/g" /etc/gitlab-runner/config.toml
sed -i "s/ADD-KEY-HERE/$AWS_ACCESS_KEY_ID/g" /etc/gitlab-runner/config.toml
sed -i "s/ADD-SECRET-HERE/$AWS_SECRET_ACCESS_KEY/g" /etc/gitlab-runner/config.toml
```

**Note**: There seems to be a bug (bad tls error) if `docker-machine` isn't first ran manually. Refer to troubleshooting section below to first create machine manually.

**Note**: A provision script is provided to create deploy-targets (single docker nodes with compose, good for hackathons)

Bad tls error seems to be related to the following 2 files created normally created on execution of first `docker-machine create` command:
```
Creating CA: /root/.docker/machine/certs/ca.pem
Creating client certificate: /root/.docker/machine/certs/cert.pem
```

(Re)start runner:

```
gitlab-runner restart
```

Alternatively, a command similar to this may be used (requires to manually get all values)
```
sudo gitlab-runner register --non-interactive \
    --url https://gitlab.example.com/ci \
    --registration-token [the REGISTRATION token here] \
    --executor "docker+machine" \
    --name "auto-scale-runner-aws" \
    --limit 10 \
    --docker-image "docker:latest" \
    --docker-privileged \
    --machine-idle-nodes 3 \
    --machine-idle-time 2700 \
    --machine-max-builds 10 \
    --machine-machine-driver "amazonec2" \
    --machine-machine-name "auto-scale-runners-%s.gitlab.example.com" \
    --machine-machine-options "amazonec2-access-key=AKI****" \
    --machine-machine-options "amazonec2-secret-key=8TC****" \
    --machine-machine-options "amazonec2-region=ap-southeast-1" \
    --machine-machine-options "amazonec2-vpc-id=vpc-asd****" \
    --machine-machine-options "amazonec2-instance-type=m4.large" \
    --machine-machine-options "amazonec2-request-spot-instance=true" \
    --machine-machine-options "amazonec2-spot-price=0.50" \
    --machine-machine-options "engine-storage-driver=overlay \
    --machine-machine-options "engine-registry-mirror=http://$(hostname -i):6000/"
```

- [docker-machine AWS options](https://docs.docker.com/machine/drivers/aws/)
- [runner advanced config](https://docs.gitlab.com/runner/configuration/advanced-configuration.html)
- [building docker images](https://www.gitlab.com/help/ci/docker/using_docker_build.md#use-docker-in-docker-executor)

### Troubleshooting

Monitor the log in 1 window:
```
tail -f /var/log/cloud-init-output.log # review provisioning script
journalctl -f -u gitlab-runner
```

Clean up existing builders
```
sudo -i
gitlab-runner stop
docker-machine ls -q | xargs docker-machine rm --force
```

Manually creating a runner with Docker Machine:
```
export AWS_ACCESS_KEY_ID=AKI.................
export AWS_SECRET_ACCESS_KEY=8T......................................
export AWS_VPC_ID=..........
export AWS_SUBNET_ID=...........
export AWS_DEFAULT_REGION=ap-southeast-1
export AWS_INSTANCE_TYPE=m4.large
docker-machine create -d amazonec2 --engine-storage-driver=overlay runner-test-gitlab
eval $(docker-machine env runner-test-gitlab)
docker version
eval $(docker-machine env -u)
docker-machine rm runner-test-gitlab
```

Review gitlab config & restart runner:
```
vim /etc/gitlab-runner/config.toml
gitlab-runner restart
```

See also: troubleshooting gitlab-runner with [gitlab-runner commands](https://docs.gitlab.com/runner/commands/README.html)

## Gitlab Registry:

Once a Repository has been created, docker images can be pushed to it:

```
docker login registry.example.com
Username: <gitlab username>
Password: <gitlab password>
```

```
docker tag ...
docker push
```

Using the Gitlab Registry in CI Builds - [see docs](https://docs.gitlab.com/ce/user/project/new_ci_build_permissions_model.html#container-registry)

```
test:
   script:
      - docker login -u gitlab-ci-token -p $CI_BUILD_TOKEN $CI_REGISTRY
      - docker build -t $CI_REGISTRY_IMAGE:latest
```


## Distributed Docker Registry Mirroring

In AWS Console, allow necessary ports between `docker-machine` security group and the `gitlab_runner` security group (currently this is actually the `gitlab_host` security group, but should be split in the future) to ensure they can use the `gitlab_runner` as the registry mirror.

Next, On the gitlab runner:
```
ssh ubuntu@$(terraform gitlab_runner_ip)
hostname -i
sudo -i
# open config to modify MachineOptions
vim /etc/gitlab-runner/config.toml
```

Note Private IP printed above and add into `MachineOptions`:
```
   "engine-registry-mirror=http://<private-ip>:6000"
```

- [Installation Instructions](https://docs.gitlab.com/runner/install/autoscaling.html#install-docker-registry)
- [Background information](https://docs.gitlab.com/runner/configuration/autoscale.html#distributed-docker-registry-mirroring)

## Optional:

### Update AMIs

AMIs are automatically updated through Terraform the `aws_ami` data source which uses `aws ec2 describe-images` API calls in the background.

Current query ran by terraform approximately equates to:

```
aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=*hvm*ssd*-16.04*"
```

See [AWS describe-images cli ref](http://docs.aws.amazon.com/cli/latest/reference/ec2/describe-images.html) for filter names.

Alternatively, visit [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/locator/ec2/) to query available amis.

### High Availability

Current setup lacks High Availability - refer to [Gitlab documentation](https://about.gitlab.com/high-availability/)

### SMTP setup

#### Current

Current email configuration is fully [templated](https://www.terraform.io/docs/providers/template/d/file.html) and uses [cloud-init](http://cloudinit.readthedocs.io/en/latest/topics/examples.html#including-users-and-groups).

#### AWS Email Service

Original setup used AWS Email service:

[credentials](https://github.com/comerford/tf-aws-gitlab/blob/master/conf/gitlab.rb#L290) and [region](https://github.com/comerford/tf-aws-gitlab/blob/master/conf/gitlab.rb#L288) settings in gitlab.rb (will start, but mail won't work)

### Tips & Scripts

[Pre-populate users](https://gist.github.com/dnozay/188f256839d4739ca3e4#pre-populate-users)

## Clean Up:

You will need to clean up runners created by Docker-Machine before running `terraform destroy`!
```
ssh ubuntu@$(terraform output gitlab_runner_ip)
sudo -i
gitlab-runner stop
docker-machine ls -q | xargs docker-machine rm
exit
```
If you forgot to do this, the Internet Gateway will fail to detach from VPC and `terraform destroy` will time out.

Empty the s3 bucket:
```
aws s3 rm --recursive s3://<bucket-name>/ELBAccessLogs/
```

(Terraform destroy may still time out due to missing dependency between instances and the subnet)

```
terraform plan -destroy
terraform destroy
```

