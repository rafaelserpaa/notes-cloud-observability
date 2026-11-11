variable "comment" {
  type    = string
  default = ""
}

variable "origin_domain_name" {
  description = "Nome da origem coberto pelo certificado do ALB (origin.<domínio>)."
  type        = string
}

variable "origin_protocol_policy" {
  description = "https-only (ALB) ou http-only (Grafana na EC2)."
  type        = string
  default     = "https-only"
}

variable "origin_http_port" {
  description = "Porta HTTP da origem; só vale com origin_protocol_policy = http-only."
  type        = number
  default     = 80
}

variable "aliases" {
  description = "Nomes alternativos (CNAMEs) da distribuição, ex.: app.<domínio>."
  type        = list(string)
}

variable "certificate_arn" {
  description = "Certificado ACM em us-east-1."
  type        = string
}

variable "price_class" {
  type    = string
  default = "PriceClass_All"
}

variable "zone_id" {
  type = string
}
