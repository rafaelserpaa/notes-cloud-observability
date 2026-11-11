variable "repository_name" {
  type = string
}

variable "force_delete" {
  description = "Se true, o terraform destroy apaga o repositório mesmo com imagens."
  type        = bool
  default     = false
}
