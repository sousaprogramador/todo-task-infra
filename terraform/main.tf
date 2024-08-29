provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "sa-east-1a"
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "sa-east-1b"
}

resource "aws_security_group" "ecs_sg" {
  name   = "ecs-security-group"
  vpc_id = aws_vpc.main.id

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

# Lookup for existing ECR repositories
data "aws_ecr_repository" "redis_repo" {
  name  = "redis"
  count = length(try([aws_ecr_repository.redis_repo.name], [])) == 0 ? 0 : 1
}

data "aws_ecr_repository" "rabbitmq_repo" {
  name  = "rabbitmq"
  count = length(try([aws_ecr_repository.rabbitmq_repo.name], [])) == 0 ? 0 : 1
}

data "aws_ecr_repository" "mongodb_repo" {
  name  = "mongo"
  count = length(try([aws_ecr_repository.mongodb_repo.name], [])) == 0 ? 0 : 1
}

# Create new ECR repositories only if they do not exist
resource "aws_ecr_repository" "redis_repo" {
  count                = length(data.aws_ecr_repository.redis_repo.*.name) == 0 ? 1 : 0
  name                 = "redis"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "rabbitmq_repo" {
  count                = length(data.aws_ecr_repository.rabbitmq_repo.*.name) == 0 ? 1 : 0
  name                 = "rabbitmq"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "mongodb_repo" {
  count                = length(data.aws_ecr_repository.mongodb_repo.*.name) == 0 ? 1 : 0
  name                 = "mongo"
  image_tag_mutability = "MUTABLE"
}

# Redis Task Definition
resource "aws_ecs_task_definition" "redis" {
  family                   = "redis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "redis"
      image     = "${data.aws_ecr_repository.redis_repo.repository_url}:latest"
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
  family                   = "rabbitmq"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  container_definitions = jsonencode([
    {
      name      = "rabbitmq"
      image     = "${data.aws_ecr_repository.rabbitmq_repo.repository_url}:latest"
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
  family                   = "mongodb"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  container_definitions = jsonencode([
    {
      name      = "mongodb"
      image     = "${data.aws_ecr_repository.mongodb_repo.repository_url}:latest"
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
