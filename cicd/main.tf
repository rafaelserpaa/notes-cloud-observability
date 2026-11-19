# Stack do pipeline (bootstrap). Fica separada da stack principal de propósito:
# o pipeline aplica a stack principal, e a role de deploy não consegue alterar
# o próprio pipeline, as roles dele nem o bucket de estado.
module "cicd" {
  source = "../modules/cicd"

  name                       = "notas"
  github_repository          = var.github_repository
  existing_connection_arn    = var.existing_connection_arn
  branch                     = var.branch
  notification_emails        = var.notification_emails
  require_manual_approval    = var.require_manual_approval
  buildspec_from_repository  = var.buildspec_from_repository
  buildspec_dir              = "${path.module}/../buildspecs"
  state_bucket_force_destroy = var.state_bucket_force_destroy
}
