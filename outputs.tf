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
