# ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Lightsail Container Service
resource "aws_lightsail_container_service" "app_service" {
  name        = "${var.app_name}-service"
  power       = var.lightsail_power
  scale       = var.lightsail_scale
  is_disabled = false

  private_registry_access {
    ecr_image_puller_role {
      is_active = true
    }
  }
}

# IAM Role Policy to allow Lightsail to pull from ECR
# Lightsail manages the role creation, we just need to ensure permissions if strictly needed, 
# but `private_registry_access` block above handles the heavy lifting usually.
# However, for explicit control or if we need to attach policies:
data "aws_iam_policy_document" "lightsail_ecr_access" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.app_repo.arn]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }
}

# Note: Lightsail creates a service-linked role. We rely on the `private_registry_access` block.
# We will create a deployment version resource. 
# IMPORTANT: This resource will fail if the image doesn't exist yet. 
# We use a null_resource or accept that the user must push the image first.
# To avoid the "chicken and egg" problem, we can make the deployment resource optional or assume user follows the guide.

resource "aws_lightsail_container_service_deployment_version" "app_deployment" {
  service_name = aws_lightsail_container_service.app_service.name

  container {
    container_name = var.app_name
    image          = "${aws_ecr_repository.app_repo.repository_url}:latest"

    ports = {
      80 = "HTTP"
    }
  }

  public_endpoint {
    container_name = var.app_name
    container_port = 80
    health_check {
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout_seconds     = 2
      interval_seconds    = 5
      path                = "/"
      success_codes       = "200-499"
    }
  }
  
  # Ensure we don't try to deploy before the service is ready
  depends_on = [aws_lightsail_container_service.app_service]
}
