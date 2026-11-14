output "backend_instance_id" {
  description = "Session Manager na EC2 de backend (docker ps, túneis)."
  value       = aws_instance.backend.id
}

output "backend_private_ip" {
  value = aws_instance.backend.private_ip
}

output "otlp_endpoint" {
  description = "Valor de OTEL_EXPORTER_OTLP_ENDPOINT nas tasks."
  value       = "http://${aws_instance.backend.private_ip}:4318"
}

output "grafana_instance_id" {
  value = aws_instance.grafana.id
}

output "grafana_public_ip" {
  value = aws_eip.grafana.public_ip
}

output "grafana_url" {
  value = "http://${aws_eip.grafana.public_ip}:3000"
}

output "backend_security_group_id" {
  value = aws_security_group.backend.id
}

output "grafana_security_group_id" {
  value = aws_security_group.grafana.id
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}
