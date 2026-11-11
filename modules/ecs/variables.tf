variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "task_family" {
  type = string
}

variable "service_name" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "execution_role_name" {
  type = string
}

variable "image" {
  description = "URI completa da imagem, com tag."
  type        = string
}

variable "container_name" {
  type = string
}

variable "container_port" {
  type = number
}

variable "task_cpu" {
  type = number
}

variable "task_memory" {
  type = number
}

variable "desired_count" {
  type = number
}

variable "health_check_grace_period_seconds" {
  type    = number
  default = 120
}

variable "subnet_ids" {
  description = "Subnets privadas de app (PrivateFargate A e B)."
  type        = list(string)
}

variable "security_group_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  type = string
}
