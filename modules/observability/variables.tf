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
  default = "obs" # a AWS não aceita nome de SG começando com "sg-"
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
