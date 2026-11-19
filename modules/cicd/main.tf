data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.region
  partition = data.aws_partition.current.partition

  pipeline_name = "${var.name}-pipeline"
  pipeline_arn  = "arn:${local.partition}:codepipeline:${local.region}:${local.account}:${local.pipeline_name}"

  ecr_registry           = "${local.account}.dkr.ecr.${local.region}.amazonaws.com"
  app_ecr_repository_uri = "${local.ecr_registry}/${var.app_ecr_repository_name}"
  app_ecr_repository_arn = "arn:${local.partition}:ecr:${local.region}:${local.account}:repository/${var.app_ecr_repository_name}"
  obs_ecr_repository_arn = "arn:${local.partition}:ecr:${local.region}:${local.account}:repository/${var.obs_ecr_repository_prefix}/*"

  # Cada projeto do CodeBuild: role (menor privilégio por tipo de trabalho),
  # modo privilegiado (Docker), timeout e grupos de relatório.
  projects = {
    seguranca = {
      description = "Fitness functions de segurança: gitleaks (histórico), pip-audit (SCA) e Bandit (SAST)"
      role        = "checks"
      privileged  = false
      compute     = "BUILD_GENERAL1_SMALL"
      timeout     = 20
      reports     = []
    }
    iac = {
      description = "Fitness functions de IaC: terraform fmt/validate, tflint e Trivy config"
      role        = "checks"
      privileged  = false
      compute     = "BUILD_GENERAL1_SMALL"
      timeout     = 20
      reports     = ["trivy"]
    }
    observabilidade = {
      description = "Fitness function de observabilidade: POST /notas gera span HTTP e span do INSERT no mesmo trace"
      role        = "checks"
      privileged  = true
      compute     = "BUILD_GENERAL1_SMALL"
      timeout     = 20
      reports     = ["fitness"]
    }
    imagem = {
      description = "Build das imagens, Bandit/pip-audit no artefato, Trivy (CVE crítica com correção) e push no ECR com a tag do commit"
      role        = "imagem"
      privileged  = true
      compute     = "BUILD_GENERAL1_MEDIUM"
      timeout     = 40
      reports     = ["trivy"]
    }
    plan = {
      description = "terraform plan da stack principal com a imagem do commit (role somente leitura)"
      role        = "plan"
      privileged  = false
      compute     = "BUILD_GENERAL1_SMALL"
      timeout     = 30
      reports     = []
    }
    deploy = {
      description = "terraform apply do plano aprovado, espelho das imagens do backend e verificações pós-deploy"
      role        = "deploy"
      privileged  = true
      compute     = "BUILD_GENERAL1_SMALL"
      timeout     = 120
      reports     = []
    }
  }

  project_names = { for k, _ in local.projects : k => "${var.name}-${k}" }
  project_arns  = { for k, n in local.project_names : k => "arn:${local.partition}:codebuild:${local.region}:${local.account}:project/${n}" }

  roles = toset(distinct([for p in local.projects : p.role]))
  role_projects = {
    for r in local.roles : r => [for k, p in local.projects : k if p.role == r]
  }

  report_groups = merge([
    for k, p in local.projects : { for r in p.reports : "${k}-${r}" => k }
  ]...)

  terraform_env = {
    TF_STATE_BUCKET                     = aws_s3_bucket.this["state"].id
    TF_STATE_KEY                        = var.state_key
    TF_STATE_KMS_KEY_ID                 = aws_kms_key.this.arn
    TFVARS_SECRET_ID                    = aws_secretsmanager_secret.tfvars.arn
    TF_VAR_iam_permissions_boundary_arn = aws_iam_policy.workload_boundary.arn
  }

  project_env = {
    seguranca       = {}
    iac             = {}
    observabilidade = { DOCKERHUB_SECRET_ID = aws_secretsmanager_secret.dockerhub.arn }
    imagem = {
      ECR_REPOSITORY_URI  = local.app_ecr_repository_uri
      CONTAINER_NAME      = var.container_name
      DOCKERHUB_SECRET_ID = aws_secretsmanager_secret.dockerhub.arn
    }
    plan   = local.terraform_env
    deploy = merge(local.terraform_env, { DOCKERHUB_SECRET_ID = aws_secretsmanager_secret.dockerhub.arn })
  }
}
