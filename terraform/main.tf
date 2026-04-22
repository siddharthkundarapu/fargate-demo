terraform {
  required_version = "~> 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# ─── DATA SOURCES ────────────────────────────────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

# Look up the main route table for the default VPC
data "aws_route_table" "main" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# ─── INTERNET GATEWAY ────────────────────────────────────────────────────────
# The default VPC had a blackhole route (old IGW was deleted).
# We created a new IGW and fixed the route manually via CLI.
# These resources now manage that state in Terraform.

resource "aws_internet_gateway" "main" {
  vpc_id = data.aws_vpc.default.id

  tags = {
    Name = "fargate-demo-igw"
  }
}

resource "aws_route" "default_internet" {
  route_table_id         = data.aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# ─── SECURITY GROUPS ─────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "fargate-demo-alb-sg"
  description = "Allow HTTP inbound to the load balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
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

resource "aws_security_group" "ecs_tasks" {
  name        = "fargate-demo-ecs-sg"
  description = "Allow inbound from ALB only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─── LOAD BALANCER ───────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "fargate-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids
  depends_on         = [aws_internet_gateway.main]
}

resource "aws_lb_target_group" "app" {
  name        = "fargate-demo-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ─── ECS CLUSTER ─────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "fargate-demo-cluster"
}

# ─── TASK DEFINITION ─────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "app" {
  family                   = "fargate-demo-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = data.aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "fargate-demo"
      image     = "303981612052.dkr.ecr.us-west-2.amazonaws.com/fargate-demo:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ─── ECS SERVICE ─────────────────────────────────────────────────────────────

resource "aws_ecs_service" "app" {
  name            = "fargate-demo-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "fargate-demo"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]
}

# ─── OUTPUTS ─────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "Hit this URL to reach the app"
  value       = "http://${aws_lb.main.dns_name}"
}