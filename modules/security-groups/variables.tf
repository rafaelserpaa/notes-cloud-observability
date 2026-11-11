variable "vpc_id" {
  type = string
}

variable "app_port" {
  description = "Porta em que as tasks escutam (gunicorn)."
  type        = number
}

variable "db_ingress_enabled" {
  description = "false remove a regra 5432 do sg db (simula a falha do Passo 9)."
  type        = bool
  default     = true
}

variable "db_port" {
  description = "Porta do Aurora PostgreSQL."
  type        = number
  default     = 5432
}
