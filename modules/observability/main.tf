# Observabilidade em duas camadas:
#
#   EC2 grafana  (subnet pública, EIP)  -> só o Grafana; 3000 aberta apenas para allowed_cidrs
#   EC2 backend  (subnet privada, sem IP público, sem NAT)
#                -> otel-collector (4318), Prometheus (9090), Tempo (3200), Loki (3100), Alertmanager (9093)
#
#   tasks (sg app) --OTLP/HTTP 4318--> backend <--9090/3200/3100/9093-- grafana <--3000-- seu IP
#                                      backend --3128 (squid)--> grafana --443--> discord.com
#
# O backend não tem rota para a internet (sem NAT; os VPC Endpoints só cobrem serviços
# da AWS). Para o Alertmanager notificar o Discord, a EC2 do Grafana roda um squid
# que aceita só o IP do backend e só destinos *.discord.com (proxy_url no Alertmanager).
# Os IPs privados são fixos (cidrhost) para quebrar o ciclo: o backend precisa do IP
# do proxy e o Grafana precisa do IP do backend.
#
# Arquivos: secrets.tf, iam.tf, security_groups.tf, backend.tf, grafana.tf.

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
