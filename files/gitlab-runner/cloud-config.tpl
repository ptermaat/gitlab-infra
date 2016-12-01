#cloud-config
# Cloud config for gitlab server
repo_update: true
repo_upgrade: all
packages:
  - python-pip
  - jq
  - parallel

runcmd:
  - gitlab-runner stop
  - bin/sh -c "docker run -d -p 6000:5000 -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io --restart always --name registry registry:2"

output:
  all: '| tee -a /var/log/cloud-init-output.log'

write_files:
  - path: /root/provision-deploy-targets.sh
    permissions: '0755'
    content: |
      !/bin/bash
      export AWS_VPC_ID=${vpc_id}
      export AWS_SUBNET_ID=${subnet_id}
      export AWS_DEFAULT_REGION=${aws_region}
      # use spot instances at 50% of on-demand price
      # use c3 (better networking & ssd instance storage)
      export AWS_INSTANCE_TYPE=c3.large
      export AWS_SPOT_PRICE=0.066

      create-vm() {
        name=$1
        docker-machine create -d amazonec2 \
          --amazonec2-request-spot-instance \
          --amazonec2-spot-price $AWS_SPOT_PRICE \
          --engine-registry-mirror=http://$(hostname -i):6000 \
          --engine-storage-driver=overlay \
          $name  #> $name.log 2>&1

        docker-machine ssh $name "sudo curl -Lo /usr/local/bin/docker-compose \
          https://github.com/docker/compose/releases/download/1.9.0/docker-compose-`uname -s`-`uname -m` && \
          sudo chmod +x /usr/local/bin/docker-compose" # >> $name.log 2>&1

        SERVER_IP=$(docker-machine ip $name)
        SSHKEY=$(docker-machine inspect $name | jq -r .Driver.SSHKeyPath | xargs cat)

        echo -e "[$name]\n  IP=$SERVER_IP\n  KEY=\"$SSHKEY\"\n" > $name.cfg
        echo "Done"
      }
      # create-vm "gitlab-deploy-master"
      export -f create-vm

      for i in {3..15}
      do
        echo "creating gitlab-deploy-target-$i"
        # sem --no-notice -j 5 create-vm "gitlab-deploy-target-$i"
        create-vm "gitlab-deploy-target-$i"
      done
  - path: /etc/gitlab-runner/config.toml
    content: |
      concurrent = 10    # at most 10 concurrent builds
      check_interval = 5 # check every 5 seconds for new builds

      [[runners]]
        name = "auto-scale-runner-aws"
        limit = 15 # at most 15 machines created
        url = "${external_url}"
        token = "ADD-TOKEN-HERE" # sudo gitlab-runner register
        executor = "docker+machine"
        [runners.docker]
          tls_verify = false
          image = "docker:latest" # docker image required for dind
          privileged = true       # privileged required for dind builds
          disable_cache = false
          volumes = ["/cache"]
          services = ["docker:dind"]
        [runners.cache]
          Type = "s3"   # The Runner is using a distributed cache with Amazon S3 service
          ServerAddress = "s3-${aws_region}.amazonaws.com"
          AccessKey = "ADD-KEY-HERE"
          SecretKey = "ADD-SECRET-HERE"
          BucketName = "${s3_bucket}"
          Insecure = false
        [runners.machine]
          IdleCount = 2   # There must be 2 machines in Idle state - when Off Peak time mode is off
          IdleTime = 2700 # Each machine can be in Idle state up to 2700 seconds (after this it will be removed) - when Off Peak time mode is off
          MaxBuilds = 100 # Each machine can handle up to 100 builds in a row (after this it will be removed)
          MachineDriver = "amazonec2"
          MachineName = "%s-gitlab"
          MachineOptions = [
            "amazonec2-access-key=ADD-KEY-HERE",
            "amazonec2-secret-key=ADD-SECRET-HERE",
            "amazonec2-region=${aws_region}",
            "amazonec2-vpc-id=${vpc_id}",
            "amazonec2-instance-type=${machine_instance_size}",
            "engine-storage-driver=overlay",
            "amazonec2-subnet-id=${subnet_id}",
          ]
          OffPeakIdleCount = 0
          OffPeakIdleTime = 0

