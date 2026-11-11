


resource "aws_db_subnet_group" "this" {
  name       = var.subnet_group_name
  subnet_ids = var.subnet_ids
  tags       = { Name = var.subnet_group_name }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.cluster_identifier
  engine             = "aurora-postgresql" 
  engine_mode        = "provisioned"       
  engine_version     = var.engine_version
  database_name      = var.database_name
  port               = 5432


  master_username             = var.master_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  storage_encrypted      = true


  enable_http_endpoint = var.enable_data_api

  backup_retention_period   = var.backup_retention_days
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.cluster_identifier}-final"
  deletion_protection       = var.deletion_protection
  apply_immediately         = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity 
    max_capacity = var.max_capacity

    seconds_until_auto_pause = var.min_capacity == 0 ? var.seconds_until_auto_pause : null
  }
}


resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${var.cluster_identifier}-instance-1"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  availability_zone   = var.writer_az
  publicly_accessible = false
  promotion_tier      = 0
}


resource "aws_rds_cluster_instance" "reader" {
  count = var.create_reader ? 1 : 0

  identifier          = "${var.cluster_identifier}-instance-2"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  availability_zone   = var.reader_az
  publicly_accessible = false
  promotion_tier      = 1

  depends_on = [aws_rds_cluster_instance.writer]
}
