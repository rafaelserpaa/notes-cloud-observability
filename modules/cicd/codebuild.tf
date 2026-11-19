resource "aws_cloudwatch_log_group" "codebuild" {
  for_each = local.project_names

  name              = "/aws/codebuild/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

# Grupos de relatório criados aqui, com retenção e sem exportação definidas. O nome
# segue a convenção <projeto>-<chave em reports: no buildspec>.
resource "aws_codebuild_report_group" "this" {
  for_each = local.report_groups

  name           = "${var.name}-${each.key}"
  type           = "TEST"
  delete_reports = true

  export_config {
    type = "NO_EXPORT"
  }
}

resource "aws_codebuild_project" "this" {
  for_each = local.projects

  name               = local.project_names[each.key]
  description        = each.value.description
  service_role       = aws_iam_role.codebuild[each.value.role].arn
  build_timeout      = each.value.timeout
  queued_timeout     = 60
  encryption_key     = aws_kms_key.this.arn
  project_visibility = "PRIVATE"

  # plan e deploy mexem no estado: nunca dois ao mesmo tempo.
  concurrent_build_limit = contains(["plan", "deploy"], each.key) ? 1 : null

  source {
    type = "CODEPIPELINE"
    # Fixado no projeto (padrão) ou lido do commit (buildspec_from_repository = true).
    buildspec = var.buildspec_from_repository ? "buildspecs/${each.key}.yml" : file("${var.buildspec_dir}/${each.key}.yml")
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type                        = "LINUX_CONTAINER"
    compute_type                = each.value.compute
    image                       = var.codebuild_image
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = each.value.privileged

    dynamic "environment_variable" {
      for_each = local.project_env[each.key]
      content {
        name  = environment_variable.key
        value = environment_variable.value
        type  = "PLAINTEXT"
      }
    }
  }

  dynamic "cache" {
    for_each = each.value.privileged ? [1] : []
    content {
      type  = "LOCAL"
      modes = ["LOCAL_DOCKER_LAYER_CACHE"]
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.codebuild[each.key].name
    }
    s3_logs {
      status = "DISABLED"
    }
  }

  depends_on = [
    aws_iam_role_policy.codebuild_base,
    aws_codebuild_report_group.this,
  ]
}
