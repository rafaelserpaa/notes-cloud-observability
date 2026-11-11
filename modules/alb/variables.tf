variable "name" {
  type = string
}

variable "target_group_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets públicas (Pub A e B)."
  type        = list(string)
}

variable "security_group_id" {
  type = string
}

variable "target_port" {
  type = number
}

variable "health_check_path" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "ssl_policy" {
  description = "Política TLS do listener (a recomendada pelo console)."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "zone_id" {
  type = string
}

variable "origin_fqdn" {
  description = "Ex.: origin.labdenuvemarquiteturavinicius.click"
  type        = string
}
