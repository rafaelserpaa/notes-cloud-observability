output "pipeline_name" {
  value = module.cicd.pipeline_name
}

output "pipeline_url" {
  value = module.cicd.pipeline_url
}

output "connection_arn" {
  value = module.cicd.connection_arn
}

output "connection_status" {
  description = "PENDING até a conexão ser autorizada no console (Developer Tools > Settings > Connections)."
  value       = module.cicd.connection_status
}

output "state_bucket" {
  value = module.cicd.state_bucket
}

output "artifact_bucket" {
  value = module.cicd.artifact_bucket
}

output "kms_key_arn" {
  value = module.cicd.kms_key_arn
}

output "tfvars_secret_id" {
  value = module.cicd.tfvars_secret_id
}

output "dockerhub_secret_id" {
  value = module.cicd.dockerhub_secret_id
}

output "permissions_boundary_arn" {
  value = module.cicd.permissions_boundary_arn
}

output "codebuild_role_arns" {
  value = module.cicd.codebuild_role_arns
}

output "backend_config" {
  description = "terraform -chdir=cicd output -raw backend_config > backend.hcl"
  value       = module.cicd.backend_config
}
