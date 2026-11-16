data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_subnet" "backend" {
  id = var.backend_subnet_id
}

data "aws_subnet" "grafana" {
  id = var.grafana_subnet_id
}

locals {
  discord_enabled = nonsensitive(var.discord_webhook_url != null)

  backend_private_ip = cidrhost(data.aws_subnet.backend.cidr_block, var.backend_host_number)
  grafana_private_ip = cidrhost(data.aws_subnet.grafana.cidr_block, var.grafana_host_number)
  egress_proxy_port  = 3128
}
