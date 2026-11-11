
resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id             = var.vpc_id
  service_name       = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]

  private_dns_enabled = true

  tags = { Name = "vpce-${each.key}" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids

  tags = { Name = "vpce-s3" }
}
