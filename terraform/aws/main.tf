# 1. Obtener la información del repositorio ECR existente (o crearlo si decides cambiar el nombre)
data "aws_ecr_repository" "app_repo" {
  name = var.app_name
}

# 2. Obtener la AMI (Imagen de sistema operativo) más reciente de Amazon Linux 2023
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# 3. Crear un Security Group (Firewall) para la VM
resource "aws_security_group" "app_sg" {
  name        = "${var.app_name}-sg"
  description = "Permitir trafico HTTP y SSH"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

# 4. Crear un Rol de IAM para que la VM pueda descargar la imagen de ECR
resource "aws_iam_role" "ec2_ecr_role" {
  name = "${var.app_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.app_name}-profile"
  role = aws_iam_role.ec2_ecr_role.name
}

# 5. Crear la Máquina Virtual (Instancia EC2)
resource "aws_instance" "app_vm" {
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.micro" # Puedes cambiarlo a t2.micro si estás en la capa gratuita estricta
  security_groups      = [aws_security_group.app_sg.name]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  # Este script se ejecuta al encender la VM por primera vez
  user_data = <<-EOF
              #!/bin/bash
              # Actualizar el sistema e instalar Docker
              dnf update -y
              dnf install -y docker
              systemctl start docker
              systemctl enable docker

              # Instalar aws-cli para el login en ECR
              dnf install -y aws-cli

              # Loguearse en el ECR y descargar la imagen usando el Rol de IAM
              aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${data.aws_ecr_repository.app_repo.repository_url}
              
              # Ejecutar el contenedor (asegúrate de haber subido una imagen con tag 'latest')
              docker run -d -p 80:${var.container_port} --name ${var.app_name} --restart always ${data.aws_ecr_repository.app_repo.repository_url}:latest
              EOF

  tags = {
    Name = "${var.app_name}-vm"
  }
}
