# Menor privilégio (SEC11-BP07): uma role por tipo de trabalho, nenhuma access key.
#
#   checks  -> seguranca, iac, observabilidade: só logs, relatórios, artefatos e a conexão
#   imagem  -> + push SOMENTE no repositório ECR da aplicação
#   plan    -> + leitura da conta (sem escrita) e do estado
#   deploy  -> + escrita nos serviços da stack principal; IAM só com prefixo e boundary
#
# Todas confiam no CodeBuild apenas para os projetos delas (aws:SourceArn), o que
# evita o "confused deputy".

data "aws_iam_policy_document" "codebuild_assume" {
  for_each = local.roles

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [for p in local.role_projects[each.key] : local.project_arns[p]]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  for_each = local.roles

  name               = "${var.name}-codebuild-${each.key}"
  description        = "CodeBuild ${join(", ", local.role_projects[each.key])}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume[each.key].json
}

# --------------------------------------------------------------------------
# Base de todas as roles do CodeBuild
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "codebuild_base" {
  for_each = local.roles

  statement {
    sid     = "LogsDosProprios"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = flatten([
      for p in local.role_projects[each.key] : [
        aws_cloudwatch_log_group.codebuild[p].arn,
        "${aws_cloudwatch_log_group.codebuild[p].arn}:*",
      ]
    ])
  }

  # Com o grupo referenciado pelo nome no buildspec, o CodeBuild chama
  # CreateReportGroup mesmo quando o grupo já existe; o escopo fica nos grupos
  # do próprio projeto.
  statement {
    sid = "RelatoriosDeTeste"
    actions = [
      "codebuild:CreateReportGroup",
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases",
      "codebuild:BatchPutCodeCoverages",
    ]
    resources = [
      for p in local.role_projects[each.key] :
      "arn:${local.partition}:codebuild:${local.region}:${local.account}:report-group/${local.project_names[p]}-*"
    ]
  }

  statement {
    sid       = "ArtefatosDoPipeline"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.this["artifacts"].arn}/*"]
  }

  statement {
    sid       = "BucketDeArtefatos"
    actions   = ["s3:GetBucketLocation", "s3:GetBucketAcl"]
    resources = [aws_s3_bucket.this["artifacts"].arn]
  }

  statement {
    sid = "ChaveDoPipeline"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.this.arn]
  }

  # Clone completo (Full clone) pela conexão, sem token pessoal.
  statement {
    sid       = "CloneCompletoPelaConexao"
    actions   = ["codeconnections:UseConnection", "codestar-connections:UseConnection"]
    resources = [aws_codeconnections_connection.github.arn]
  }
}

resource "aws_iam_role_policy" "codebuild_base" {
  for_each = local.roles

  name   = "base"
  role   = aws_iam_role.codebuild[each.key].id
  policy = data.aws_iam_policy_document.codebuild_base[each.key].json
}

# Credencial opcional do Docker Hub (pull da imagem base sem limite anônimo).
resource "aws_iam_role_policy" "dockerhub" {
  for_each = toset(["checks", "imagem", "deploy"])

  name = "dockerhub-pull"
  role = aws_iam_role.codebuild[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "CredencialDoDockerHub"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.dockerhub.arn]
    }]
  })
}

# --------------------------------------------------------------------------
# imagem: push somente no repositório da aplicação (trecho da apostila, Seção 7)
# --------------------------------------------------------------------------
resource "aws_iam_role_policy" "imagem" {
  name = "push-so-no-repositorio-do-lab"
  role = aws_iam_role.codebuild["imagem"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LoginNoEcr"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "PushSoNoRepositorioDoLab"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages",
        ]
        Resource = [local.app_ecr_repository_arn]
      },
    ]
  })
}

# --------------------------------------------------------------------------
# plan e deploy: estado e tfvars
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "terraform_state" {
  for_each = toset(["plan", "deploy"])

  statement {
    sid       = "ListarBucketDeEstado"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this["state"].arn]
  }

  statement {
    sid       = "LerEstado"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this["state"].arn}/${var.state_key}"]
  }

  # Lock nativo do S3 (use_lockfile): o plan também trava o estado.
  statement {
    sid       = "LockDoEstado"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.this["state"].arn}/${var.state_key}.tflock"]
  }

  dynamic "statement" {
    for_each = each.key == "deploy" ? [1] : []
    content {
      sid       = "GravarEstado"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this["state"].arn}/${var.state_key}"]
    }
  }

  statement {
    sid       = "LerTfvars"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.tfvars.arn]
  }
}

resource "aws_iam_role_policy" "terraform_state" {
  for_each = toset(["plan", "deploy"])

  name   = "terraform-state"
  role   = aws_iam_role.codebuild[each.key].id
  policy = data.aws_iam_policy_document.terraform_state[each.key].json
}

# Leitura do que a stack principal gerencia (refresh do plan). Sem escrita.
data "aws_iam_policy_document" "workload_read" {
  statement {
    sid = "LeituraDosServicosDaStack"
    actions = [
      "sts:GetCallerIdentity",
      "ec2:Describe*",
      "ec2:Get*",
      "ecs:Describe*",
      "ecs:List*",
      "elasticloadbalancing:Describe*",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "acm:Describe*",
      "acm:List*",
      "acm:GetCertificate",
      "cloudfront:Get*",
      "cloudfront:List*",
      "cloudfront:Describe*",
      "route53:Get*",
      "route53:List*",
      "budgets:View*",
      "budgets:Describe*",
      "budgets:List*",
      "logs:Describe*",
      "logs:List*",
      "iam:Get*",
      "iam:List*",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ListSecrets",
      "kms:DescribeKey",
      "ssm:DescribeParameters",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AmiPublicaDoAl2023"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"]
  }

  # O refresh de aws_secretsmanager_secret_version lê o valor.
  statement {
    sid       = "ValoresDosSegredosDaStack"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for p in var.workload_secret_prefixes : "arn:${local.partition}:secretsmanager:${local.region}:${local.account}:secret:${p}*"]
  }

  statement {
    sid       = "DecifrarSegredosViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "workload_read" {
  name        = "${var.name}-workload-read"
  description = "Leitura dos recursos da stack principal (terraform plan)"
  policy      = data.aws_iam_policy_document.workload_read.json
}

resource "aws_iam_role_policy_attachment" "workload_read" {
  for_each = toset(["plan", "deploy"])

  role       = aws_iam_role.codebuild[each.key].name
  policy_arn = aws_iam_policy.workload_read.arn
}

# --------------------------------------------------------------------------
# deploy: escrita nos serviços da stack principal, só em us-east-1
# --------------------------------------------------------------------------
locals {
  workload_role_arn    = "arn:${local.partition}:iam::${local.account}:role/${var.workload_name_prefix}*"
  workload_profile_arn = "arn:${local.partition}:iam::${local.account}:instance-profile/${var.workload_name_prefix}*"
}

data "aws_iam_policy_document" "workload_write" {
  # Serviços inteiros da stack. Recursos do pipeline (CodeBuild, CodePipeline,
  # S3, KMS, roles notas-*) ficam fora desta lista.
  statement {
    sid = "ServicosDaStack"
    actions = [
      "ec2:*",
      "ecs:*",
      "elasticloadbalancing:*",
      "rds:*",
      "acm:*",
      "cloudfront:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid       = "Route53DaZonaDoLab"
    actions   = ["route53:ChangeResourceRecordSets", "route53:GetChange", "route53:AssociateVPCWithHostedZone"]
    resources = ["arn:${local.partition}:route53:::hostedzone/*", "arn:${local.partition}:route53:::change/*"]
  }

  statement {
    sid       = "OrcamentoDoLab"
    actions   = ["budgets:*"]
    resources = ["arn:${local.partition}:budgets::${local.account}:budget/*"]
  }

  statement {
    sid     = "LogGroupsDaStack"
    actions = ["logs:*"]
    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${var.workload_log_group_prefix}*",
      "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${var.workload_log_group_prefix}*:*",
    ]
  }

  statement {
    sid       = "SegredosDaStack"
    actions   = ["secretsmanager:*"]
    resources = [for p in var.workload_secret_prefixes : "arn:${local.partition}:secretsmanager:${local.region}:${local.account}:secret:${p}*"]
  }

  statement {
    sid       = "SenhaAleatoriaDoSecretsManager"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  statement {
    sid       = "RepositoriosEcrDaStack"
    actions   = ["ecr:*"]
    resources = [local.app_ecr_repository_arn, local.obs_ecr_repository_arn]
  }

  statement {
    sid       = "LoginNoEcr"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Aurora (senha gerenciada) e Secrets Manager usam chaves gerenciadas pela AWS.
  statement {
    sid       = "ChavesGerenciadasViaServico"
    actions   = ["kms:CreateGrant", "kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "rds.${local.region}.amazonaws.com",
        "secretsmanager.${local.region}.amazonaws.com",
      ]
    }
  }

  # IAM: só roles/instance profiles com o prefixo da stack e SEMPRE com o
  # permission boundary. Mesmo que alguém altere o Terraform para criar uma
  # role "lab-admin", ela nunca terá mais do que o boundary permite.
  statement {
    sid = "RolesDaStackComBoundary"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = [local.workload_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid = "ManutencaoDasRolesDaStack"
    actions = [
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [local.workload_role_arn]
  }

  statement {
    sid = "InstanceProfilesDaStack"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = [local.workload_profile_arn]
  }

  statement {
    sid       = "PassRoleSoParaEcsEEc2"
    actions   = ["iam:PassRole"]
    resources = [local.workload_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "RolesVinculadasAosServicos"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "rds.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "NuncaRemoverOBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_write" {
  name        = "${var.name}-workload-deploy"
  description = "Escrita nos recursos da stack principal (terraform apply pelo pipeline)"
  policy      = data.aws_iam_policy_document.workload_write.json
}

resource "aws_iam_role_policy_attachment" "workload_write" {
  role       = aws_iam_role.codebuild["deploy"].name
  policy_arn = aws_iam_policy.workload_write.arn
}

# --------------------------------------------------------------------------
# Permission boundary das roles que a stack principal cria (execution role do
# ECS e as duas roles das EC2 de observabilidade): o máximo que elas podem ter.
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid = "PullDeImagensEcr"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:Describe*",
      "ecr:List*",
      "ecr:GetLifecyclePolicy",
      "ecr:GetLifecyclePolicyPreview",
      "ecr:GetRepositoryPolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "LogsDasTasks"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    sid       = "SegredosDaStack"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for p in var.workload_secret_prefixes : "arn:${local.partition}:secretsmanager:${local.region}:${local.account}:secret:${p}*"]
  }

  statement {
    sid       = "DecifrarSegredos"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  # Ações de AmazonSSMManagedInstanceCore (Session Manager nas EC2).
  statement {
    sid = "SessionManager"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "${var.name}-workload-boundary"
  description = "Permission boundary obrigatório nas roles criadas pela stack principal via pipeline"
  policy      = data.aws_iam_policy_document.workload_boundary.json
}

# --------------------------------------------------------------------------
# CodePipeline: escrita à mão (a role gerada pelo console é bem mais ampla)
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.pipeline_arn]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.name}-codepipeline"
  description        = "CodePipeline ${local.pipeline_name}"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    sid       = "ArtefatosDoPipeline"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = ["${aws_s3_bucket.this["artifacts"].arn}/*"]
  }

  statement {
    sid       = "BucketDeArtefatos"
    actions   = ["s3:GetBucketVersioning", "s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.this["artifacts"].arn]
  }

  statement {
    sid       = "ChaveDoPipeline"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = [aws_kms_key.this.arn]
  }

  statement {
    sid       = "OrigemGitHub"
    actions   = ["codeconnections:UseConnection", "codestar-connections:UseConnection"]
    resources = [aws_codeconnections_connection.github.arn]
  }

  statement {
    sid       = "SoOsProjetosDoPipeline"
    actions   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds", "codebuild:StopBuild"]
    resources = values(local.project_arns)
  }

  statement {
    sid       = "AvisoDeAprovacao"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.pipeline.arn]
  }
}

resource "aws_iam_role_policy" "codepipeline" {
  name   = "pipeline"
  role   = aws_iam_role.codepipeline.id
  policy = data.aws_iam_policy_document.codepipeline.json
}
