provider "aws" {
  region = var.aws_region
}

# Reutilizar a Role IAM existente
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = data.aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# VPC Configuration - Criar apenas se necessário
variable "create_vpc" {
  description = "Se deve criar uma nova VPC"
  type        = bool
  default     = false
}

resource "aws_vpc" "main" {
  count      = var.create_vpc ? 1 : 0
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet_1" {
  count             = var.create_vpc ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "sa-east-1a"
}

resource "aws_subnet" "subnet_2" {
  count             = var.create_vpc ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "sa-east-1b"
}

resource "aws_security_group" "ecs_sg" {
  vpc_id = var.create_vpc ? aws_vpc.main[0].id : var.existing_vpc_id
  name   = "ecs-security-group"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-fargate-cluster"
}

# Check and Create ECR Repositories if not exist
resource "null_resource" "create_redis_repo" {
  provisioner "local-exec" {
    command = <<EOT
      aws ecr describe-repositories --repository-names redis --region ${var.aws_region} || \
      aws ecr create-repository --repository-name redis --region ${var.aws_region}
    EOT
  }
}

resource "null_resource" "create_rabbitmq_repo" {
  provisioner "local-exec" {
    command = <<EOT
      aws ecr describe-repositories --repository-names rabbitmq --region ${var.aws_region} || \
      aws ecr create-repository --repository-name rabbitmq --region ${var.aws_region}
    EOT
  }
}

resource "null_resource" "create_mongodb_repo" {
  provisioner "local-exec" {
    command = <<EOT
      aws ecr describe-repositories --repository-names mongo --region ${var.aws_region} || \
      aws ecr create-repository --repository-name mongo --region ${var.aws_region}
    EOT
  }
}

# Redis Task Definition
resource "aws_ecs_task_definition" "redis" {
  depends_on               = [null_resource.create_redis_repo]
  family                   = "redis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "redis"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/redis:latest"
      essential = true
      portMappings = [
        {
          containerPort = 6379
          hostPort      = 6379
        }
      ]
    }
  ])
}

# RabbitMQ Task Definition
resource "aws_ecs_task_definition" "rabbitmq" {
  depends_on               = [null_resource.create_rabbitmq_repo]
  family                   = "rabbitmq"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "rabbitmq"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/rabbitmq:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5672
          hostPort      = 5672
        },
        {
          containerPort = 15672
          hostPort      = 15672
        }
      ]
    }
  ])
}

# MongoDB Task Definition
resource "aws_ecs_task_definition" "mongodb" {
  depends_on               = [null_resource.create_mongodb_repo]
  family                   = "mongodb"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "mongodb"
      image     = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/mongo:latest"
      essential = true
      portMappings = [
        {
          containerPort = 27017
          hostPort      = 27017
        }
      ]
    }
  ])
}

# Redis Service
resource "aws_ecs_service" "redis_service" {
  name            = "redis-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

# RabbitMQ Service
resource "aws_ecs_service" "rabbitmq_service" {
  name            = "rabbitmq-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.rabbitmq.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}

# MongoDB Service
resource "aws_ecs_service" "mongodb_service" {
  name            = "mongodb-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.mongodb.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
}
