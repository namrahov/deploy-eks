# Trafik zenciri:  internet -> ALB SG -> ECS SG -> RDS SG
# Her seviye yalniz ozunden evvelki SG-ni qebul edir. Hec yerde 0.0.0.0/0 acilmir (ALB-den basqa).

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "Internetden ALB-ye HTTP/HTTPS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS ucun (sertifikat elave etdikden sonra ac):
  # ingress {
  #   from_port   = 443
  #   to_port     = 443
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project}-ecs-sg"
  description = "Yalniz ALB-den container port-a"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "ALB -> container"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Egress lazimdir: ECR-den image cekmek, Secrets Manager, CloudWatch Logs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Yalniz ECS task-lardan Postgres"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "ECS -> Postgres"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = { Name = "${var.project}-rds-sg" }
}
