variable "name" {
  description = "Prefixo dos recursos do pipeline (notas-pipeline, notas-seguranca, ...)."
  type        = string
  default     = "notas"
}

variable "github_repository" {
  description = "Repositório no formato dono/nome, lido pela conexão do GitHub."
  type        = string
}

variable "branch" {
  description = "Branch que dispara o pipeline (implantação contínua)."
  type        = string
  default     = "main"
}

variable "existing_connection_arn" {
  description = "ARN de uma conexão do GitHub já criada e autorizada no console (CodeConnections). null = o módulo cria a conexão <name>-github."
  type        = string
  default     = null
}

variable "require_manual_approval" {
  description = "true = entrega contínua (alguém aprova o plano antes do deploy); false = implantação contínua."
  type        = bool
  default     = true
}

variable "notification_emails" {
  description = "E-mails que recebem pedidos de aprovação e falhas/sucessos do pipeline (confirmar a inscrição no e-mail da AWS)."
  type        = list(string)
  default     = []
}

variable "buildspec_from_repository" {
  description = "false (recomendado) = os buildspecs ficam fixados nos projetos do CodeBuild a cada apply desta stack, e quem só faz push não consegue desligar um portão. true = o CodeBuild lê buildspecs/*.yml do commit, como no laboratório."
  type        = bool
  default     = false
}

variable "buildspec_dir" {
  description = "Diretório local com os buildspecs (usado quando buildspec_from_repository = false)."
  type        = string
}

variable "codebuild_image" {
  description = "Imagem gerenciada do CodeBuild (a da apostila)."
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "artifact_retention_days" {
  description = "Por quantos dias os artefatos do pipeline (plano, imagedefinitions.json) ficam no S3."
  type        = number
  default     = 30
}

variable "secret_recovery_window_days" {
  description = "Janela de recuperação dos segredos do pipeline. 0 apaga na hora (prático no lab, para recriar a stack com o mesmo nome)."
  type        = number
  default     = 0
}

variable "state_bucket_force_destroy" {
  description = "Só para a limpeza final: true permite que o destroy apague o bucket de estado com todas as versões."
  type        = bool
  default     = false
}

variable "state_key" {
  description = "Chave do estado da stack principal no bucket de estado."
  type        = string
  default     = "notas-da-nuvem/terraform.tfstate"
}

variable "app_ecr_repository_name" {
  description = "Repositório ECR da aplicação (criado pela stack principal). Único em que o CodeBuild de imagem pode fazer push."
  type        = string
  default     = "labarquiteturanuvem"
}

variable "obs_ecr_repository_prefix" {
  description = "Prefixo dos repositórios ECR espelhados do backend de observabilidade."
  type        = string
  default     = "lab-obs"
}

variable "container_name" {
  description = "Nome do container na task definition (vai para o imagedefinitions.json)."
  type        = string
  default     = "app"
}

variable "workload_name_prefix" {
  description = "Prefixo das roles e instance profiles que a stack principal cria (lab-nuvem-ecsTaskExecutionRole, lab-obs-*). A role de deploy só gerencia IAM com esse prefixo."
  type        = string
  default     = "lab-"
}

variable "workload_secret_prefixes" {
  description = "Prefixos dos segredos que a stack principal gerencia (lab-obs/* e os segredos gerenciados pelo RDS)."
  type        = list(string)
  default     = ["lab-obs/", "rds!"]
}

variable "workload_log_group_prefix" {
  description = "Prefixo dos log groups da stack principal."
  type        = string
  default     = "/ecs/"
}
