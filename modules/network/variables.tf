variable "name" {
  description = "Nome da VPC e do Internet Gateway."
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Use ao menos 2 AZs (o RDS exige subnets em duas AZs diferentes)."
  }
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "app_subnet_cidrs" {
  type = list(string)
}

variable "data_subnet_cidrs" {
  type = list(string)

  validation {
    condition     = length(var.data_subnet_cidrs) >= 2
    error_message = "O DB subnet group precisa de ao menos 2 subnets."
  }
}
