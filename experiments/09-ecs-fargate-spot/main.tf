# ECS Fargate on Spot playground: one nginx task, 100% FARGATE_SPOT.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Cluster ---------------------------------------------------------------

resource "aws_ecs_cluster" "play" {
  name = "play-spot"
}

# Capacity providers are attached to the cluster; services then reference
# them in a capacity_provider_strategy. FARGATE is attached too so we can
# later experiment with base/weight mixes without touching the cluster.
resource "aws_ecs_cluster_capacity_providers" "play" {
  cluster_name       = aws_ecs_cluster.play.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# --- IAM -------------------------------------------------------------------

# Execution role: what the Fargate agent uses to pull the image and ship logs.
resource "aws_iam_role" "task_execution" {
  name = "play-nginx-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: what the container itself can do. Only needed here for ECS Exec
# (SSM messages channel — same plumbing as Session Manager).
resource "aws_iam_role" "task" {
  name = "play-nginx-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "task_exec_command" {
  name = "ecs-exec"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

# --- Task definition ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/ecs/play-nginx"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "nginx" {
  family                   = "play-nginx"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # ARM64 on FARGATE_SPOT is supported since Sep 2024 (platform 1.4.0+).
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name      = "nginx"
    image     = "public.ecr.aws/nginx/nginx:mainline-alpine"
    essential = true

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]

    # On a Spot interruption ECS sends SIGTERM, then SIGKILL after
    # stopTimeout. 120s is the Fargate maximum and matches the 2-minute
    # Spot warning window.
    stopTimeout = 120

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.nginx.name
        "awslogs-region"        = "ap-south-1"
        "awslogs-stream-prefix" = "nginx"
      }
    }
  }])
}

# --- Service -----------------------------------------------------------------

resource "aws_security_group" "nginx" {
  name        = "play-nginx"
  description = "nginx on Fargate Spot"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_service" "nginx" {
  name            = "nginx"
  cluster         = aws_ecs_cluster.play.id
  task_definition = aws_ecs_task_definition.nginx.arn
  desired_count   = 1

  # 100% Spot: every task lands on FARGATE_SPOT. No base entry, so nothing
  # is guaranteed on-demand capacity — deliberate, this is the lesson.
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.nginx.id]
    assign_public_ip = true
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  enable_execute_command = true

  # Strategy changes roll out via a new deployment; the provider requires
  # this flag to update capacity_provider_strategy in place.
  force_new_deployment = true

  depends_on = [aws_ecs_cluster_capacity_providers.play]
}

# --- Interruption audit trail --------------------------------------------------
# Stopped-task details (stopCode, stoppedReason) are only kept for a short
# while after the task dies. This EventBridge rule writes every STOPPED task
# event in the cluster to a log group so Spot interruptions leave evidence.

resource "aws_cloudwatch_log_group" "task_events" {
  name              = "/ecs/play-task-events"
  retention_in_days = 7
}

resource "aws_cloudwatch_event_rule" "task_stopped" {
  name        = "play-ecs-task-stopped"
  description = "Capture STOPPED task events for the play-spot cluster"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      clusterArn = [aws_ecs_cluster.play.arn]
      lastStatus = ["STOPPED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "task_stopped_to_logs" {
  rule = aws_cloudwatch_event_rule.task_stopped.name
  arn  = aws_cloudwatch_log_group.task_events.arn
}

# EventBridge needs an explicit resource policy to write into the log group.
resource "aws_cloudwatch_log_resource_policy" "eventbridge" {
  policy_name = "play-eventbridge-to-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
      }
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.task_events.arn}:*"
    }]
  })
}

# --- Outputs -------------------------------------------------------------------

output "cluster_name" {
  value = aws_ecs_cluster.play.name
}

output "service_name" {
  value = aws_ecs_service.nginx.name
}

output "task_events_log_group" {
  value       = aws_cloudwatch_log_group.task_events.name
  description = "Where STOPPED task events (incl. SpotInterruption) are recorded"
}

output "get_public_ip_command" {
  description = "The task IP changes on every replacement; fetch the current one with this"
  value       = <<-EOT
    aws ecs list-tasks --cluster play-spot --service-name nginx --profile sourav --region ap-south-1 --query 'taskArns[0]' --output text | xargs -I{} aws ecs describe-tasks --cluster play-spot --tasks {} --profile sourav --region ap-south-1 --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text | xargs -I{} aws ec2 describe-network-interfaces --network-interface-ids {} --profile sourav --region ap-south-1 --query 'NetworkInterfaces[0].Association.PublicIp' --output text
  EOT
}
