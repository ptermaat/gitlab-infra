#cloud-config
# Cloud config for gitlab server
repo_update: true
repo_upgrade: all


runcmd:
  # Reconfigure gitlab
  - gitlab-ctl reconfigure

output:
  all: '| tee -a /var/log/cloud-init-output.log'

write_files:
  - path: /etc/gitlab/gitlab.rb
    content: |
      ## Latest options listed at:
      ## https://gitlab.com/gitlab-org/omnibus-gitlab/blob/master/files/gitlab-config-template/gitlab.rb.template

      ## Url on which GitLab will be reachable.
      ## For more details on configuring external_url see:
      ## https://gitlab.com/gitlab-org/omnibus-gitlab/blob/master/doc/settings/configuration.md#configuring-the-external-url-for-gitlab
      external_url '${external_url}'

      ############################
      # gitlab.yml configuration #
      ############################

      gitlab_rails['gitlab_email_from'] = '${smtp_from_email}'
      gitlab_rails['gitlab_email_display_name'] = '${smtp_email_display_name}'
      gitlab_rails['gitlab_email_reply_to'] = '${smtp_email_reply_to}'

      ################################
      # GitLab email server settings #
      ################################
      # see https://gitlab.com/gitlab-org/omnibus-gitlab/blob/master/doc/settings/smtp.md#smtp-settings
      # Use smtp instead of sendmail/postfix.

      gitlab_rails['smtp_enable'] = true
      gitlab_rails['smtp_address'] = "${smtp_host}"
      gitlab_rails['smtp_port'] = ${smtp_port}
      gitlab_rails['smtp_user_name'] = "${smtp_user}"
      gitlab_rails['smtp_password'] = "${smtp_password}"
      gitlab_rails['smtp_authentication'] = "login"
      gitlab_rails['smtp_enable_starttls_auto'] = true

      ###############################
      # Container Registry settings #
      ###############################
      # See https://docs.gitlab.com/ce/administration/container_registry.html
      #

      registry_external_url '${registry_external_url}'

      ## Settings used by GitLab application
      gitlab_rails['registry_enabled'] = true

      ################
      # GitLab Nginx #
      ################
      ## see: https://gitlab.com/gitlab-org/omnibus-gitlab/tree/master/doc/settings/nginx.md

      nginx['enable'] = true
      nginx['listen_port'] = 80 # override only if you use a reverse proxy: https://gitlab.com/gitlab-org/omnibus-gitlab/blob/master/doc/settings/nginx.md#setting-the-nginx-listen-port
      nginx['listen_https'] = false # override only if your reverse proxy internally communicates over HTTP: https://gitlab.com/gitlab-org/omnibus-gitlab/blob/master/doc/settings/nginx.md#supporting-proxied-ssl
      nginx['proxy_set_headers'] = {
       "Host" => "$http_host",
       "X-Real-IP" => "$remote_addr",
       "X-Forwarded-For" => "$proxy_add_x_forwarded_for",
       "X-Forwarded-Proto" => "https",
       "X-Forwarded-Ssl" => "on"
      }

      ##################
      # Registry NGINX #
      ##################

      registry_nginx['listen_port'] = 80 # override only if you use a reverse proxy: https://gitlab.com/gitlab-org/omnibus-gitlab/blob/master/doc/settings/nginx.md#setting-the-nginx-listen-port
      registry_nginx['listen_https'] = false # override only if your reverse proxy internally communicates over HTTP: https://gitlab.com/gitlab-org/omnibus-gitlab/blob/master/doc/settings/nginx.md#supporting-proxied-ssl
      registry_nginx['proxy_set_headers'] = {
        "Host" => "$http_host",
        "X-Real-IP" => "$remote_addr",
        "X-Forwarded-For" => "$proxy_add_x_forwarded_for",
        "X-Forwarded-Proto" => "https",
        "X-Forwarded-Ssl" => "on"
      }
