output "cluster_endpoint" {
  value      = aws_rds_cluster.this.endpoint
  depends_on = [aws_rds_cluster_instance.writer]
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  value = aws_rds_cluster.this.port
}

output "database_name" {
  value = aws_rds_cluster.this.database_name
}

output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "master_user_secret_arn" {
  description = "ARN do secret rds!cluster-... (chaves JSON: username, password)."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}
