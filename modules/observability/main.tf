# Observabilidade em duas camadas:
#
#   EC2 grafana  (subnet pública, EIP)  -> só o Grafana; 3000 aberta apenas para allowed_cidrs
#   EC2 backend  (subnet privada, sem IP público, sem NAT)
#                -> otel-collector (4318), Prometheus (9090), Tempo (3200), Loki (3100), Alertmanager (9093)
#
#   tasks (sg app) --OTLP/HTTP 4318--> backend <--9090/3200/3100/9093-- grafana <--3000-- seu IP
#
# Arquivos: secrets.tf, iam.tf, security_groups.tf, backend.tf, grafana.tf.

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  discord_enabled = nonsensitive(var.discord_webhook_url != null)
}
