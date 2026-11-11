variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets dos endpoints de interface (PrivateFargate A e B)."
  type        = list(string)
}

variable "security_group_id" {
  description = "SG endpoint (443 vindo do sg app)."
  type        = string
}

variable "route_table_ids" {
  description = "Route tables que recebem a rota do endpoint gateway do S3."
  type        = list(string)
}

variable "interface_services" {
  type    = list(string)
  default = ["ecr.api", "ecr.dkr", "secretsmanager", "logs"]
}
