output "certificate_arn" {
  description = "ARN do certificado já validado."
  value       = aws_acm_certificate_validation.this.certificate_arn
}
