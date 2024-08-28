output "redis_service_name" {
  description = "The name of the Redis ECS service"
  value       = aws_ecs_service.redis_service.name
}

output "rabbitmq_service_name" {
  description = "The name of the RabbitMQ ECS service"
  value       = aws_ecs_service.rabbitmq_service.name
}

output "mongodb_service_name" {
  description = "The name of the MongoDB ECS service"
  value       = aws_ecs_service.mongodb_service.name
}
