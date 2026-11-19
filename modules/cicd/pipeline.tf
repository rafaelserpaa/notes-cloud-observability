locals {
  # Todo build recebe o commit da origem: a tag da imagem é o início do SHA.
  commit_env = jsonencode([{
    name  = "COMMIT_ID"
    value = "#{SourceVariables.CommitId}"
    type  = "PLAINTEXT"
  }])
}

resource "aws_codepipeline" "this" {
  name           = local.pipeline_name
  role_arn       = aws_iam_role.codepipeline.arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED"

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.this["artifacts"].bucket

    encryption_key {
      type = "KMS"
      id   = aws_kms_key.this.arn
    }
  }

  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.branch]
        }
        file_paths {
          includes = ["**"]
          excludes = var.trigger_excluded_paths
        }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      namespace        = "SourceVariables"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn    = aws_codeconnections_connection.github.arn
        FullRepositoryId = var.github_repository
        BranchName       = var.branch
        # Full clone: o gitleaks precisa do histórico inteiro.
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  # Portões baratos primeiro (shift left), em paralelo.
  stage {
    name = "Validacao"

    dynamic "action" {
      for_each = {
        Seguranca       = "seguranca"
        IaC             = "iac"
        Observabilidade = "observabilidade"
      }
      content {
        name            = action.key
        category        = "Build"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        run_order       = 1
        input_artifacts = ["SourceArtifact"]

        configuration = {
          ProjectName          = aws_codebuild_project.this[action.value].name
          EnvironmentVariables = local.commit_env
        }
      }
    }
  }

  stage {
    name = "Imagem"
    action {
      name             = "BuildTrivyEcr"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "ImagemVariables"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["ImagemArtifact"]

      configuration = {
        ProjectName          = aws_codebuild_project.this["imagem"].name
        EnvironmentVariables = local.commit_env
      }
    }
  }

  stage {
    name = "Plano"
    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "PlanVariables"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["PlanArtifact"]

      configuration = {
        ProjectName          = aws_codebuild_project.this["plan"].name
        EnvironmentVariables = local.commit_env
      }
    }
  }

  # Com aprovação: entrega contínua. Sem: implantação contínua (Seção 8).
  dynamic "stage" {
    for_each = var.require_manual_approval ? [1] : []
    content {
      name = "Aprovacao"
      action {
        name     = "RevisarPlano"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          NotificationArn    = aws_sns_topic.pipeline.arn
          CustomData         = "Commit #{SourceVariables.CommitId} (imagem #{ImagemVariables.IMAGE_TAG}). #{PlanVariables.PLAN_SUMMARY}. Revise o plano no log do TerraformPlan antes de aprovar."
          ExternalEntityLink = "#{PlanVariables.BUILD_URL}"
        }
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact", "PlanArtifact"]

      configuration = {
        ProjectName          = aws_codebuild_project.this["deploy"].name
        PrimarySource        = "SourceArtifact"
        EnvironmentVariables = local.commit_env
      }
    }
  }
}
