variable "name" {
  type = string
}

variable "limit_usd" {
  type = number
}

variable "notification_emails" {
  type = list(string)

  validation {
    condition     = length(var.notification_emails) > 0
    error_message = "Informe ao menos um e-mail para os alertas do orçamento."
  }
}

variable "alerts" {
  description = "Alertas: gasto real acima de 85% e 100%, e previsto acima de 100%."
  type = list(object({
    threshold = number
    type      = string
  }))
  default = [
    { threshold = 85, type = "ACTUAL" },
    { threshold = 100, type = "ACTUAL" },
    { threshold = 100, type = "FORECASTED" },
  ]
}
