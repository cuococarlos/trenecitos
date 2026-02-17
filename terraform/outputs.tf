output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "lightsail_service_url" {
  description = "URL of the Lightsail service"
  value       = aws_lightsail_container_service.app_service.url
}
