# =============================================================================
# AndysMotors - EP4 ADY1103 - Infraestructura base (continuidad de la EP3)
# Instancia con las seis plataformas en Docker Compose, CloudWatch Agent
# y el inyector de metricas de negocio en Node.js.
# =============================================================================

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "andys" {
  name        = "andys-motors-ep4-sg"
  description = "AndysMotors EP4: SSH y HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (EC2 Instance Connect)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (HAProxy de AndysMotors)"
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

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_instance" "andys" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.tipo_instancia
  iam_instance_profile   = "LabInstanceProfile"
  vpc_security_group_ids = [aws_security_group.andys.id]
  monitoring             = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url         = var.repo_url
    region           = var.region
    duracion_trafico = var.duracion_trafico_seg
    log_group        = aws_cloudwatch_log_group.plataformas.name
    log_group_debug  = aws_cloudwatch_log_group.agente_debug.name
    inyector_js_b64  = base64gzip(file("${path.module}/../inyector/inyector-metricas.js"))
    package_json_b64 = base64gzip(file("${path.module}/../inyector/package.json"))
  })
  user_data_replace_on_change = true

  # Solo el nombre. El resto de etiquetas se aplica con Tag Editor y Terraform
  # no debe borrarlas en un apply posterior.
  tags = {
    Name = "andys-motors"
  }

  lifecycle {
    ignore_changes = [tags, tags_all, volume_tags]
  }
}
