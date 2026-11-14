variable "region" {
  description = "Região de todos os recursos."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.region == "us-east-1"
    error_message = "O certificado é compartilhado entre CloudFront e ALB, então a região precisa ser us-east-1."
  }
}

variable "account_id" {
  description = "ID da conta AWS permitida (null desativa a trava)."
  type        = string
  default     = null
}

variable "project" {
  description = "Nome do projeto, usado em tags e nomes."
  type        = string
  default     = "lab-nuvem"
}

variable "budget_limit_usd" {
  description = "Limite mensal do orçamento, em USD."
  type        = number
  default     = 100
}

variable "budget_emails" {
  description = "E-mails que recebem os alertas do orçamento."
  type        = list(string)
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "AZs usadas, na ordem A, B."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Pub(A), Pub(B) — ALB."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_subnet_cidrs" {
  description = "PrivateFargate(A), PrivateFargate(B) — tasks e VPC Endpoints."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "data_subnet_cidrs" {
  description = "PrivateAurora(A), PrivateAurora(B) — Aurora."
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "db_cluster_identifier" {
  type    = string
  default = "lab-aurora2"
}

variable "db_engine_version" {
  description = "Versão do Aurora PostgreSQL. Mínimo de 0 ACU exige 16.3+, 15.7+, 14.12+ ou 13.15+."
  type        = string
  default     = "16.15"
}

variable "db_name" {
  description = "Banco inicial (a aplicação espera em DB_NAME)."
  type        = string
  default     = "notasdb"
}

variable "db_master_username" {
  type    = string
  default = "postgres"
}

variable "db_min_acu" {
  description = "Mínimo de ACUs. 0 = pausa automática sem uso."
  type        = number
  default     = 0
}

variable "db_max_acu" {
  type    = number
  default = 2
}

variable "ecr_repository_name" {
  type    = string
  default = "labarquiteturanuvem"
}

variable "image_tag" {
  description = "Tag (imutável) da imagem que o ECS vai rodar."
  type        = string
  default     = "v1-1.0.0"
}

variable "ecs_cluster_name" {
  type    = string
  default = "lab-cluster"
}

variable "task_family" {
  type    = string
  default = "lab-test"
}

variable "ecs_service_name" {
  type    = string
  default = "lab-service"
}

variable "container_name" {
  type    = string
  default = "app"
}

variable "container_port" {
  description = "Porta do gunicorn (sg app, target group e health check)."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "CPU da task em unidades (256 = 0,25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memória da task em MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Tasks desejadas (uma por AZ)."
  type        = number
  default     = 2
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "alb_name" {
  type    = string
  default = "alb-lab"
}

variable "target_group_name" {
  type    = string
  default = "tg-lab"
}

variable "domain_name" {
  description = "Domínio registrado, com hosted zone pública no Route 53."
  type        = string
  default     = "labdenuvemarquiteturavinicius.click"
}

variable "app_subdomain" {
  description = "Endereço público (CloudFront)."
  type        = string
  default     = "app"
}

variable "origin_subdomain" {
  description = "Endereço de origem (ALB), coberto pelo certificado curinga."
  type        = string
  default     = "origin"
}

variable "cloudfront_price_class" {
  type    = string
  default = "PriceClass_All"
}

# ------------------------------------------------------------------ observabilidade

variable "enable_observability" {
  description = "Liga a EC2 de observabilidade, o CloudFront do Grafana, o loadgen e a imagem OTel na aplicação."
  type        = bool
  default     = true
}

variable "otel_image_tag" {
  description = "Tag da imagem da aplicação instrumentada (target app do Dockerfile), usada quando enable_observability = true. ECR é IMMUTABLE: imagem nova = tag nova."
  type        = string
  default     = "app-2.1.0"
}

variable "loadgen_image_tag" {
  description = "Tag da imagem do gerador de carga (target loadgen do Dockerfile)."
  type        = string
  default     = "loadgen-1.0.0"
}

variable "loadgen_desired_count" {
  description = "Tasks do notas-loadgen. Use 0 para desligar (com ele ligado o Aurora nunca pausa)."
  type        = number
  default     = 1
}

variable "obs_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "grafana_subdomain" {
  description = "Endereço público do Grafana (CloudFront), coberto pelo certificado curinga."
  type        = string
  default     = "grafana"
}

variable "discord_webhook_url" {
  description = "Webhook do Discord que recebe os alertas do Alertmanager. Deixe null para não notificar."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition = var.discord_webhook_url == null || can(regex(
      "^https://(discord|discordapp)\\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$",
      var.discord_webhook_url
    ))
    error_message = "Use a URL completa do webhook: https://discord.com/api/webhooks/<id>/<token>."
  }
}

variable "simulate_db_failure" {
  description = "Passo 9: true remove a regra 5432 do sg db e derruba o SLI. Volte para false para desfazer."
  type        = bool
  default     = false
}
