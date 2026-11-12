data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

locals {
  app_fqdn     = "${var.app_subdomain}.${var.domain_name}"
  origin_fqdn  = "${var.origin_subdomain}.${var.domain_name}"
  grafana_fqdn = "${var.grafana_subdomain}.${var.domain_name}"

  app_image = "${module.ecr.repository_url}:${var.enable_observability ? var.otel_image_tag : var.image_tag}"

  otel_environment = var.enable_observability ? [
    { name = "OTEL_SERVICE_NAME", value = "notas-da-nuvem" },
    { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = module.observability[0].otlp_endpoint },
    { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "http/protobuf" },
    { name = "OTEL_TRACES_EXPORTER", value = "otlp" },
    { name = "OTEL_METRICS_EXPORTER", value = "otlp" },
    { name = "OTEL_LOGS_EXPORTER", value = "otlp" },
    { name = "OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED", value = "true" },
  ] : []
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

  vpc_id             = module.network.vpc_id
  app_port           = var.container_port
  db_port            = 5432
  db_ingress_enabled = !var.simulate_db_failure
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

  image          = local.app_image
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

  extra_environment = local.otel_environment

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


module "observability" {
  source = "./modules/observability"
  count  = var.enable_observability ? 1 : 0

  region                = var.region
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.public_subnet_ids[0]
  app_security_group_id = module.security_groups.app_sg_id
  instance_type         = var.obs_instance_type
  grafana_fqdn          = local.grafana_fqdn
  discord_webhook_url   = var.discord_webhook_url
}

module "cloudfront_grafana" {
  source = "./modules/cloudfront"
  count  = var.enable_observability ? 1 : 0

  comment                = "labnuvem-grafana"
  origin_domain_name     = module.observability[0].public_dns
  origin_protocol_policy = "http-only"
  origin_http_port       = 3000
  aliases                = [local.grafana_fqdn]
  certificate_arn        = module.acm.certificate_arn
  price_class            = var.cloudfront_price_class
  zone_id                = data.aws_route53_zone.this.zone_id
}

module "loadgen" {
  source = "./modules/loadgen"
  count  = var.enable_observability ? 1 : 0

  region             = var.region
  cluster_name       = module.ecs.cluster_name
  execution_role_arn = module.ecs.execution_role_arn
  image              = "${module.ecr.repository_url}:${var.loadgen_image_tag}"
  target_url         = "https://${local.app_fqdn}"
  otlp_endpoint      = module.observability[0].otlp_endpoint
  desired_count      = var.loadgen_desired_count

  subnet_ids        = module.network.public_subnet_ids
  assign_public_ip  = true
  security_group_id = module.security_groups.app_sg_id
}
