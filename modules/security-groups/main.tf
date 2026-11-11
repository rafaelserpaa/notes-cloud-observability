
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "alb"
  description = "ALB - aceita apenas o CloudFront"
  vpc_id      = var.vpc_id
  tags        = { Name = "alb" }
}

resource "aws_security_group" "app" {
  name        = "app"
  description = "Tasks Fargate - aceita apenas o ALB"
  vpc_id      = var.vpc_id
  tags        = { Name = "app" }
}

resource "aws_security_group" "db" {
  name        = "db"
  description = "Aurora - aceita apenas as tasks"
  vpc_id      = var.vpc_id
  tags        = { Name = "db" }
}

resource "aws_security_group" "endpoint" {
  name        = "endpoint"
  description = "VPC Endpoints de interface - aceita apenas as tasks"
  vpc_id      = var.vpc_id
  tags        = { Name = "endpoint" }
}


resource "aws_vpc_security_group_ingress_rule" "alb_https_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS das edges do CloudFront"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "gunicorn, somente a partir do ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

moved {
  from = aws_vpc_security_group_ingress_rule.db_from_app
  to   = aws_vpc_security_group_ingress_rule.db_from_app[0]
}

# Passo 9 (falha provocada): db_ingress_enabled = false remove esta regra.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  count = var.db_ingress_enabled ? 1 : 0

  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL, somente a partir das tasks"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_from_app" {
  security_group_id            = aws_security_group.endpoint.id
  description                  = "HTTPS das tasks para os servicos da AWS"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = {
    alb      = aws_security_group.alb.id
    app      = aws_security_group.app.id
    db       = aws_security_group.db.id
    endpoint = aws_security_group.endpoint.id
  }

  security_group_id = each.value
  description       = "Saida liberada"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
