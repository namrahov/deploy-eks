resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/db-credentials"
  recovery_window_in_days = 0 # oyrenme ucun
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  # Bu JSON acarlari k8s/01-external-secret.yaml-da istifade olunur
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
    jdbc_url = "jdbc:postgresql://${aws_db_instance.main.address}:5432/${var.db_name}"
  })
}

# ---------- Security group ----------
# ECS-den ferq: burada menbe EKS node-larinin SG-sidir.
# Auto Mode-da da node-lar cluster primary SG-ni alir.

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Yalniz EKS node-larindan Postgres"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "EKS nodes -> Postgres"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id, module.eks.cluster_primary_security_group_id]
  }

  tags = { Name = "${var.project}-rds-sg" }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period         = 7
  performance_insights_enabled    = var.db_performance_insights
  enabled_cloudwatch_logs_exports = ["postgresql"]

  skip_final_snapshot = true  # prod-da false
  deletion_protection = false # prod-da true
  apply_immediately   = true

  tags = { Name = "${var.project}-postgres" }
}
