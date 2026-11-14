resource "aws_instance" "grafana" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.grafana_instance_type
  subnet_id                   = var.grafana_subnet_id
  vpc_security_group_ids      = [aws_security_group.grafana.id]
  iam_instance_profile        = aws_iam_instance_profile.grafana.name
  associate_public_ip_address = true

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/grafana_user_data.sh.tftpl", {
    region              = var.region
    secret_arn          = aws_secretsmanager_secret.grafana.arn
    grafana_image       = var.grafana_image
    backend_host        = aws_instance.backend.private_ip
    datasources         = trimspace(file("${path.module}/config/grafana-datasources.yaml"))
    dashboards_provider = trimspace(file("${path.module}/config/grafana-dashboards.yaml"))
    dashboard_sli       = trimspace(file("${path.module}/config/dashboard-sli.json"))
  }))
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = var.grafana_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.grafana_name }

  lifecycle {
    ignore_changes = [ami]

    precondition {
      condition     = length(var.grafana_allowed_cidrs) > 0
      error_message = "Defina grafana_allowed_cidrs (ex.: [\"<seu IP>/32\"]): sem ele ninguém alcança a porta 3000."
    }
  }

  depends_on = [
    aws_vpc_security_group_ingress_rule.endpoint_from_obs,
    aws_secretsmanager_secret_version.grafana,
    aws_iam_role_policy.read_grafana_secret,
    aws_iam_role_policy_attachment.grafana_ssm,
  ]
}

# IP fixo: o endereço do Grafana não muda se a instância for recriada.
resource "aws_eip" "grafana" {
  domain   = "vpc"
  instance = aws_instance.grafana.id
  tags     = { Name = var.grafana_name }
}
