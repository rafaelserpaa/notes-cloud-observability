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
