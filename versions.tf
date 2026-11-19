terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Estado remoto no bucket criado por cicd/ (lock nativo do S3, use_lockfile).
  # Configuração parcial: terraform init -backend-config=backend.hcl
  # (veja backend.hcl.example e CICD.md).
  backend "s3" {}
}
