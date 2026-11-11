provider "aws" {
  region = var.region

  allowed_account_ids = var.account_id == null ? null : [var.account_id]

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
