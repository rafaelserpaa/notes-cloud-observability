output "instance_id" {
  description = "Para o Session Manager (túnel do Alertmanager na 9093)."
  value       = aws_instance.this.id
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "otlp_endpoint" {
  description = "Valor de OTEL_EXPORTER_OTLP_ENDPOINT nas tasks."
  value       = "http://${aws_instance.this.private_ip}:4318"
}

output "public_dns" {
  description = "Origem do CloudFront do Grafana (DNS do Elastic IP)."
  value       = aws_eip.this.public_dns
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "grafana_secret_arn" {
  value = aws_secretsmanager_secret.grafana.arn
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}
