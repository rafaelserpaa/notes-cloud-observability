output "app_url" {
  description = "Endereço público da aplicação."
  value       = "https://${local.app_fqdn}"
}

output "cloudfront_domain_name" {
  value = module.cloudfront.domain_name
}

output "origin_fqdn" {
  description = "Nome que o CloudFront usa para chegar ao ALB (SNI)."
  value       = module.alb.origin_fqdn
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecr_repository_url" {
  description = "Use no docker tag/push."
  value       = module.ecr.repository_url
}

output "aurora_cluster_endpoint" {
  value = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  value = module.aurora.reader_endpoint
}

output "aurora_cluster_arn" {
  description = "Para o RDS Query Editor (Data API)."
  value       = module.aurora.cluster_arn
}

output "aurora_secret_arn" {
  description = "Secret gerenciado com usuário e senha do banco."
  value       = module.aurora.master_user_secret_arn
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "log_group_name" {
  value = module.ecs.log_group_name
}


output "grafana_url" {
  description = "Grafana (só abre a partir de grafana_allowed_cidrs). Login: admin."
  value       = var.enable_observability ? module.observability[0].grafana_url : null
}

output "grafana_admin_password" {
  description = "Senha do usuário admin do Grafana (terraform output -raw grafana_admin_password)."
  value       = var.enable_observability ? module.observability[0].grafana_admin_password : null
  sensitive   = true
}

output "obs_backend_instance_id" {
  description = "EC2 privada: aws ssm start-session --target <id>."
  value       = var.enable_observability ? module.observability[0].backend_instance_id : null
}

output "obs_grafana_instance_id" {
  value = var.enable_observability ? module.observability[0].grafana_instance_id : null
}

output "obs_otlp_endpoint" {
  value = var.enable_observability ? module.observability[0].otlp_endpoint : null
}

output "obs_image_mirror" {
  description = "Origem (Docker Hub) e destino (ECR) de cada imagem do backend; lido por scripts/mirror-images.sh."
  value       = local.obs_image_mirror
}

output "loadgen_service_name" {
  value = var.enable_observability ? module.loadgen[0].service_name : null
}
