# sg obs-grafana: 3000 só a partir de var.grafana_allowed_cidrs (seu IP /32);
#                3128 (squid) só do sg obs-backend.
# sg obs-backend: 4318 só do sg app; 9090/3200/3100/9093 só do sg obs-grafana.

resource "aws_security_group" "grafana" {
  name        = var.grafana_security_group_name
  description = "EC2 do Grafana - 3000 somente do IP autorizado"
  vpc_id      = var.vpc_id
  tags        = { Name = var.grafana_security_group_name }
}

resource "aws_vpc_security_group_ingress_rule" "grafana_ui" {
  for_each = toset(var.grafana_allowed_cidrs)

  security_group_id = aws_security_group.grafana.id
  description       = "Grafana, somente do IP autorizado"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 3000
  to_port           = 3000
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_backend" {
  security_group_id            = aws_security_group.grafana.id
  description                  = "Proxy de saida (squid) - Alertmanager do backend para o Discord"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = local.egress_proxy_port
  to_port                      = local.egress_proxy_port
}

resource "aws_vpc_security_group_egress_rule" "grafana_all" {
  security_group_id = aws_security_group.grafana.id
  description       = "Saida liberada (pull do Grafana, consultas ao backend)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}


resource "aws_security_group" "backend" {
  name        = var.backend_security_group_name
  description = "EC2 de backend - OTLP do sg app, consultas do sg obs-grafana"
  vpc_id      = var.vpc_id
  tags        = { Name = var.backend_security_group_name }
}

resource "aws_vpc_security_group_ingress_rule" "otlp_from_app" {
  security_group_id            = aws_security_group.backend.id
  description                  = "OTLP HTTP, somente tasks do sg app"
  referenced_security_group_id = var.app_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 4318
  to_port                      = 4318
}

locals {
  backend_ports_from_grafana = {
    prometheus   = 9090
    tempo        = 3200
    loki         = 3100
    alertmanager = 9093
  }
}

resource "aws_vpc_security_group_ingress_rule" "backend_from_grafana" {
  for_each = local.backend_ports_from_grafana

  security_group_id            = aws_security_group.backend.id
  description                  = "${each.key}, somente do sg ${var.grafana_security_group_name}"
  referenced_security_group_id = aws_security_group.grafana.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}

resource "aws_vpc_security_group_egress_rule" "backend_all" {
  security_group_id = aws_security_group.backend.id
  description       = "Saida liberada (sem NAT: na pratica so VPC Endpoints e a propria VPC)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}


# Os VPC Endpoints de interface têm DNS privado: Secrets Manager, ECR e SSM resolvem
# para eles a partir das duas EC2. Sem estas regras o sg endpoint descarta a conexão.
resource "aws_vpc_security_group_ingress_rule" "endpoint_from_obs" {
  for_each = {
    backend = aws_security_group.backend.id
    grafana = aws_security_group.grafana.id
  }

  security_group_id            = var.endpoint_security_group_id
  description                  = "HTTPS da EC2 obs-${each.key} para os servicos da AWS"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
