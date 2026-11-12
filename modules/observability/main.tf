
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}


resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = var.grafana_secret_name
  description             = "Senha do admin do Grafana (lab de observabilidade)"
  recovery_window_in_days = 0 
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}


locals {
  discord_enabled = nonsensitive(var.discord_webhook_url != null)
}

resource "aws_secretsmanager_secret" "discord_webhook" {
  count = local.discord_enabled ? 1 : 0

  name                    = var.discord_secret_name
  description             = "URL do webhook do Discord usada pelo Alertmanager"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "discord_webhook" {
  count = local.discord_enabled ? 1 : 0

  secret_id     = aws_secretsmanager_secret.discord_webhook[0].id
  secret_string = var.discord_webhook_url
}


resource "aws_iam_role" "this" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy" "read_grafana_secret" {
  name = "read-obs-secrets"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = concat(
        [aws_secretsmanager_secret.grafana.arn],
        aws_secretsmanager_secret.discord_webhook[*].arn,
      )
    }]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = var.role_name
  role = aws_iam_role.this.name
}


resource "aws_security_group" "this" {
  name        = var.security_group_name
  description = "EC2 de observabilidade - Grafana so pelo CloudFront, OTLP so pelas tasks"
  vpc_id      = var.vpc_id
  tags        = { Name = var.security_group_name }
}

resource "aws_vpc_security_group_ingress_rule" "grafana_from_cloudfront" {
  security_group_id = aws_security_group.this.id
  description       = "Grafana, somente das edges do CloudFront"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
}

resource "aws_vpc_security_group_ingress_rule" "otlp_from_app" {
  security_group_id            = aws_security_group.this.id
  description                  = "OTLP HTTP, somente tasks do sg-app"
  referenced_security_group_id = var.app_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 4318
  to_port                      = 4318
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Saida liberada (pull de imagens, SSM, Secrets Manager)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}


resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = true 

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region             = var.region
    secret_arn         = aws_secretsmanager_secret.grafana.arn
    grafana_fqdn       = var.grafana_fqdn
    alertmanager_image = var.alertmanager_image
    discord_secret_arn = local.discord_enabled ? aws_secretsmanager_secret.discord_webhook[0].arn : ""
  })
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" 
  }

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = var.name }

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [
    aws_secretsmanager_secret_version.grafana,
    aws_secretsmanager_secret_version.discord_webhook,
    aws_iam_role_policy.read_grafana_secret,
  ]
}

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id
  tags     = { Name = var.name }
}
