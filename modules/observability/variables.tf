variable "region" {
  type = string
}

variable "name" {
  description = "Nome da instância."
  type        = string
  default     = "lab-observabilidade"
}

variable "role_name" {
  type    = string
  default = "lab-obs-ec2"
}

variable "security_group_name" {
  type    = string
  default = "obs"
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Subnet pública onde a instância sobe."
  type        = string
}

variable "app_security_group_id" {
  description = "sg-app: único com acesso à porta 4318 (OTLP HTTP)."
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "volume_size" {
  description = "Disco raiz em GiB."
  type        = number
  default     = 16
}

variable "grafana_fqdn" {
  description = "Nome público do Grafana (alias do CloudFront), usado em GF_SERVER_ROOT_URL."
  type        = string
}

variable "grafana_secret_name" {
  description = "Nome do secret (Secrets Manager) com a senha do admin do Grafana."
  type        = string
  default     = "lab-obs/grafana-admin-password"
}

variable "discord_webhook_url" {
  description = "URL do webhook do Discord para o Alertmanager. null = sem notificação externa."
  type        = string
  default     = null
  sensitive   = true
}

variable "discord_secret_name" {
  description = "Nome do secret (Secrets Manager) com a URL do webhook do Discord."
  type        = string
  default     = "lab-obs/discord-webhook-url"
}

variable "alertmanager_image" {
  description = "Imagem do Alertmanager (>= v0.27 para discord_configs com webhook_url_file)."
  type        = string
  default     = "prom/alertmanager:v0.28.1"
}
