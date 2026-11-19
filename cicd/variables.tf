variable "region" {
  type    = string
  default = "us-east-1"
}

variable "account_id" {
  description = "ID da conta AWS permitida (null desativa a trava)."
  type        = string
  default     = null
}

variable "project" {
  description = "Mesmo valor de var.project da stack principal (tag Project)."
  type        = string
  default     = "lab-nuvem"
}

variable "github_repository" {
  description = "Repositório (dono/nome) que o pipeline lê."
  type        = string
}

variable "branch" {
  type    = string
  default = "main"
}

variable "notification_emails" {
  description = "Quem recebe os pedidos de aprovação e o resultado das execuções."
  type        = list(string)
  default     = []
}

variable "require_manual_approval" {
  description = "true = entrega contínua (aprovação do plano antes do deploy); false = implantação contínua."
  type        = bool
  default     = true
}

variable "state_bucket_force_destroy" {
  description = "Só na limpeza final (apply e depois destroy com true)."
  type        = bool
  default     = false
}

variable "buildspec_from_repository" {
  description = "false = buildspecs fixados nos projetos a cada apply desta stack (recomendado); true = lidos do commit."
  type        = bool
  default     = false
}
