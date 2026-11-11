data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

locals {
  app_fqdn    = "${var.app_subdomain}.${var.domain_name}"
  origin_fqdn = "${var.origin_subdomain}.${var.domain_name}"
}

module "budget" {
  source = "./modules/budget"

  name                = "${var.project}-mensal"
  limit_usd           = var.budget_limit_usd
  notification_emails = var.budget_emails
}

module "network" {
  source = "./modules/network"

  name                = "labnuvem"
  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  data_subnet_cidrs   = var.data_subnet_cidrs
}

module "security_groups" {
  source = "./modules/security-groups"

  vpc_id   = module.network.vpc_id
  app_port = var.container_port
  db_port  = 5432
}

module "vpc_endpoints" {
  source = "./modules/vpc-endpoints"

  region            = var.region
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.app_subnet_ids
  security_group_id = module.security_groups.endpoint_sg_id
  route_table_ids   = [module.network.private_route_table_id]
}

module "aurora" {
  source = "./modules/aurora"

  cluster_identifier = var.db_cluster_identifier
  engine_version     = var.db_engine_version
  database_name      = var.db_name
  master_username    = var.db_master_username
  min_capacity       = var.db_min_acu
  max_capacity       = var.db_max_acu

  subnet_group_name = "db-subnets"
  subnet_ids        = module.network.data_subnet_ids
  security_group_id = module.security_groups.db_sg_id
  writer_az         = var.azs[0]
  reader_az         = var.azs[1]
}

module "ecr" {
  source = "./modules/ecr"

  repository_name = var.ecr_repository_name
}

module "acm" {
  source = "./modules/acm"

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.this.zone_id
}

module "alb" {
  source = "./modules/alb"

  name              = var.alb_name
  target_group_name = var.target_group_name
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  target_port       = var.container_port
  health_check_path = var.health_check_path
  certificate_arn   = module.acm.certificate_arn

  zone_id     = data.aws_route53_zone.this.zone_id
  origin_fqdn = local.origin_fqdn
}

module "ecs" {
  source = "./modules/ecs"

  region         = var.region
  cluster_name   = var.ecs_cluster_name
  task_family    = var.task_family
  service_name   = var.ecs_service_name
  log_group_name = "/ecs/${var.ecr_repository_name}"

  execution_role_name = "${var.project}-ecsTaskExecutionRole"

  image          = "${module.ecr.repository_url}:${var.image_tag}"
  container_name = var.container_name
  container_port = var.container_port
  task_cpu       = var.task_cpu
  task_memory    = var.task_memory
  desired_count  = var.desired_count

  subnet_ids        = module.network.app_subnet_ids
  security_group_id = module.security_groups.app_sg_id
  target_group_arn  = module.alb.target_group_arn

  db_host       = module.aurora.cluster_endpoint
  db_port       = module.aurora.port
  db_name       = module.aurora.database_name
  db_secret_arn = module.aurora.master_user_secret_arn

  depends_on = [module.vpc_endpoints, module.alb]
}

module "cloudfront" {
  source = "./modules/cloudfront"

  comment            = "labnuvem"
  origin_domain_name = module.alb.origin_fqdn
  aliases            = [local.app_fqdn]
  certificate_arn    = module.acm.certificate_arn
  price_class        = var.cloudfront_price_class
  zone_id            = data.aws_route53_zone.this.zone_id
}
