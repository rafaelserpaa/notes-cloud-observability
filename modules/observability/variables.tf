variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "app_security_group_id" {
  description = "sg app: único com acesso à 4318 (OTLP HTTP) do backend."
  type        = string
}

variable "endpoint_security_group_id" {
  description = "SG dos VPC Endpoints de interface; recebe a regra 443 vinda das duas EC2."
  type        = string
}

variable "discord_webhook_url" {
  description = "URL do webhook do Discord para o Alertmanager. null = sem notificação externa."
  type        = string
  default     = null
  sensitive   = true
}

variable "grafana_secret_name" {
  description = "Nome do secret (Secrets Manager) com a senha do admin do Grafana."
  type        = string
  default     = "lab-obs/grafana-admin-password"
}

variable "discord_secret_name" {
  description = "Nome do secret (Secrets Manager) com a URL do webhook do Discord."
  type        = string
  default     = "lab-obs/discord-webhook-url"
}

# ------------------------------------------------------------------ backend (subnet privada)

variable "backend_name" {
  type    = string
  default = "lab-obs-backend"
}

variable "role_name" {
  description = "Role/instance profile da EC2 de backend."
  type        = string
  default     = "lab-obs-ec2"
}

variable "backend_security_group_name" {
  type    = string
  default = "obs-backend"
}

variable "backend_subnet_id" {
  description = "Subnet privada (PrivateFargate A): sem IP público, alcança os VPC Endpoints."
  type        = string
}

variable "backend_host_number" {
  description = "Host fixo dentro da subnet do backend (cidrhost). 250 fica longe dos IPs que a AWS distribui primeiro."
  type        = number
  default     = 250
}

variable "backend_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "backend_volume_size" {
  description = "Disco raiz em GiB (dados de Prometheus, Tempo e Loki)."
  type        = number
  default     = 20
}

variable "backend_images" {
  description = "URI completa (ECR) de cada imagem do backend: otel-collector, prometheus, tempo, loki, alertmanager."
  type        = map(string)
}

# ------------------------------------------------------------------ grafana (subnet pública)

variable "grafana_name" {
  type    = string
  default = "lab-obs-grafana"
}

variable "grafana_role_name" {
  type    = string
  default = "lab-obs-grafana"
}

variable "grafana_security_group_name" {
  type    = string
  default = "obs-grafana"
}

variable "grafana_subnet_id" {
  description = "Subnet pública (Pub A)."
  type        = string
}

variable "grafana_allowed_cidrs" {
  description = "CIDRs com acesso à 3000 (seu IP /32)."
  type        = list(string)
}

variable "grafana_host_number" {
  description = "Host fixo dentro da subnet do Grafana (cidrhost)."
  type        = number
  default     = 250
}

variable "grafana_instance_type" {
  type    = string
  default = "t3.small"
}

variable "grafana_volume_size" {
  type    = number
  default = 10
}

variable "grafana_image" {
  description = "Imagem do Grafana (baixada do Docker Hub pela subnet pública)."
  type        = string
  default     = "grafana/grafana:11.5.2"
}
