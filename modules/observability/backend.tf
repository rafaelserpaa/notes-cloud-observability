resource "aws_instance" "backend" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.backend_instance_type
  subnet_id                   = var.backend_subnet_id
  private_ip                  = local.backend_private_ip
  vpc_security_group_ids      = [aws_security_group.backend.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false

  # gzip: as configs embutidas passam do limite de 16 KB do user_data em texto.
  user_data_base64 = base64gzip(templatefile("${path.module}/templates/backend_user_data.sh.tftpl", {
    region             = var.region
    registry           = split("/", values(var.backend_images)[0])[0]
    images             = var.backend_images
    discord_secret_arn = local.discord_enabled ? aws_secretsmanager_secret.discord_webhook[0].arn : ""
    egress_proxy_url   = "http://${local.grafana_private_ip}:${local.egress_proxy_port}"
    collector_config   = trimspace(file("${path.module}/config/otel-collector.yaml"))
    prometheus_config  = trimspace(file("${path.module}/config/prometheus.yml"))
    alert_rules        = trimspace(file("${path.module}/config/alert-rules.yml"))
    tempo_config       = trimspace(file("${path.module}/config/tempo.yaml"))
    loki_config        = trimspace(file("${path.module}/config/loki.yaml"))
  }))
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.backend_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.backend_name }

  lifecycle {
    ignore_changes = [ami]

    precondition {
      condition     = alltrue([for k in ["otel-collector", "prometheus", "tempo", "loki", "alertmanager"] : contains(keys(var.backend_images), k)])
      error_message = "backend_images precisa das chaves otel-collector, prometheus, tempo, loki e alertmanager."
    }
  }

  depends_on = [
    aws_vpc_security_group_ingress_rule.endpoint_from_obs,
    aws_secretsmanager_secret_version.discord_webhook,
    aws_iam_role_policy.read_discord_secret,
    aws_iam_role_policy_attachment.ecr,
    aws_iam_role_policy_attachment.ssm,
  ]
}
