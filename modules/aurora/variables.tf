variable "cluster_identifier" {
  type = string
}

variable "engine_version" {
  type = string
}

variable "database_name" {
  type = string
}

variable "master_username" {
  type = string
}

variable "min_capacity" {
  type = number
}

variable "max_capacity" {
  type = number
}

variable "seconds_until_auto_pause" {
  description = "Tempo ocioso até pausar (só vale com min_capacity = 0)."
  type        = number
  default     = 300
}

variable "subnet_group_name" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "writer_az" {
  type = string
}

variable "reader_az" {
  type = string
}

variable "create_reader" {
  type    = bool
  default = true
}

variable "enable_data_api" {
  type    = bool
  default = true
}

variable "backup_retention_days" {
  type    = number
  default = 1
}

variable "skip_final_snapshot" {
  description = "true no lab, para o destroy não deixar snapshot cobrando."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  type    = bool
  default = false
}
