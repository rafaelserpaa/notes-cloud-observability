output "pipeline_name" {
  value = aws_codepipeline.this.name
}

output "pipeline_url" {
  value = "https://${local.region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.this.name}/view?region=${local.region}"
}

output "connection_arn" {
  value = local.connection_arn
}

output "connection_status" {
  description = "PENDING até alguém autorizar o app da AWS no GitHub pelo console."
  value       = data.aws_codestarconnections_connection.github.connection_status
}

output "state_bucket" {
  value = aws_s3_bucket.this["state"].id
}

output "artifact_bucket" {
  value = aws_s3_bucket.this["artifacts"].id
}

output "kms_key_arn" {
  value = aws_kms_key.this.arn
}

output "tfvars_secret_id" {
  value = aws_secretsmanager_secret.tfvars.arn
}

output "dockerhub_secret_id" {
  value = aws_secretsmanager_secret.dockerhub.arn
}

output "permissions_boundary_arn" {
  value = aws_iam_policy.workload_boundary.arn
}

output "notifications_topic_arn" {
  value = aws_sns_topic.pipeline.arn
}

output "codebuild_role_arns" {
  value = { for k, r in aws_iam_role.codebuild : k => r.arn }
}

output "backend_config" {
  description = "Conteúdo do backend.hcl da stack principal (terraform init -backend-config=backend.hcl)."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.this["state"].id}"
    key          = "${var.state_key}"
    region       = "${local.region}"
    encrypt      = true
    kms_key_id   = "${aws_kms_key.this.arn}"
    use_lockfile = true
  EOT
}
