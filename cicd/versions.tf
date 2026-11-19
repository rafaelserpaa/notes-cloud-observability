terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Estado local no primeiro apply (o bucket de estado nasce aqui). Depois, se
  # quiser, migre para o próprio bucket com uma chave separada:
  #   terraform init -migrate-state \
  #     -backend-config="bucket=<state_bucket>" -backend-config="key=cicd/terraform.tfstate" \
  #     -backend-config="region=us-east-1" -backend-config="use_lockfile=true" \
  #     -backend-config="encrypt=true" -backend-config="kms_key_id=<kms_key_arn>"
  # descomentando:
  # backend "s3" {}
}
