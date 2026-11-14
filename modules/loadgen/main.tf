
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = var.execution_role_arn


  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = var.name
    image     = var.image
    essential = true

    environment = concat([
      { name = "TARGET_URL", value = var.target_url },
      { name = "OTEL_SERVICE_NAME", value = var.name },
      { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = var.otlp_endpoint },
      { name = "OTEL_EXPORTER_OTLP_PROTOCOL", value = "http/protobuf" },
      { name = "OTEL_TRACES_EXPORTER", value = "otlp" },
      { name = "OTEL_METRICS_EXPORTER", value = "otlp" },
      { name = "OTEL_LOGS_EXPORTER", value = "otlp" },
      { name = "OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED", value = "true" },
    ], var.extra_environment)

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = var.name
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_name
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = var.assign_public_ip
  }
}
