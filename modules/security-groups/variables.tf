variable "vpc_id" {
  type = string
}

variable "app_port" {
  description = "Porta em que as tasks escutam (gunicorn)."
  type        = number
}

variable "db_port" {
  description = "Porta do Aurora PostgreSQL."
  type        = number
  default     = 5432
}
