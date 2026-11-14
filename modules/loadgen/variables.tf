variable "region" {
  type = string
}

variable "name" {
  type    = string
  default = "notas-loadgen"
}

variable "cluster_name" {
  type = string
}

variable "execution_role_arn" {
  description = "Mesma task execution role da aplicação. O loadgen não tem task role."
  type        = string
}

variable "image" {
  description = "URI completa da imagem do loadgen, com tag."
  type        = string
}

variable "target_url" {
  description = "URL pública da aplicação (CloudFront)."
  type        = string
}

variable "otlp_endpoint" {
  type = string
}

variable "extra_environment" {
  description = "Variáveis de ambiente adicionais (ex.: detectores de recurso OTel)."
  type        = list(object({ name = string, value = string }))
  default     = []
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  description = "1 liga o gerador; 0 desliga (o Aurora volta a pausar)."
  type        = number
  default     = 1
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "assign_public_ip" {
  description = "Necessário quando não há NAT: é o que dá ao loadgen saída para o CloudFront."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  type    = number
  default = 7
}
