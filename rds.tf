# ---------- Parol: Terraform yaradir, Secrets Manager saxlayir ----------
# Parol hec vaxt .tf faylinda ve ya ECS env variable-da acig gorunmur.
# DIQQET: random_password state faylinda saxlanilir -> state-i mutleq
# sifreli S3 backend-de saxla, git-e commit etme.

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?" # RDS-in qadaga qoydugu / @ " bosluq yoxdur
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/db-credentials"
  recovery_window_in_days = 0 # oyrenme ucun: destroy edende derhal silinsin
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
  })
}

# ---------- RDS Postgres ----------

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnets"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.project}-db-subnets" }
}

locals {
  # "16" -> postgres16, "16.14" -> postgres16. Versiya deyisende family de deyisir.
  db_major_version   = split(".", var.db_engine_version)[0]
  db_parameter_group = "postgres${local.db_major_version}"
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.project}-pg${local.db_major_version}"
  family = local.db_parameter_group

  # Yavas sorgulari loglamaq (1 saniyeden uzun)
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Major versiyani deyisende kohnesi hele instance-a bagli olur:
  # evvel yenisi yaradilmalidir, yoxsa "parameter group is in use" xetasi.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  # Free tier planinda saxlama 20 GB ile mehduddur -> autoscaling sonduruk (0 = sonulu)
  max_allocated_storage = var.free_tier_account ? 0 : 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false # KRITIK: baza internetden elcatan olmamalidir
  multi_az               = var.db_multi_az

  # Free tier hesab avtomatik backup-a icaze vermir:
  #   FreeTierRestrictionError: The specified backup retention period exceeds
  #   the maximum available to free tier customers.
  # 0 = avtomatik backup sondurulub (point-in-time recovery yoxdur).
  backup_retention_period = var.free_tier_account ? 0 : var.db_backup_retention_period
  backup_window           = var.free_tier_account ? null : "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Bunlar da free tier planinda bloklana bilir
  performance_insights_enabled    = !var.free_tier_account
  enabled_cloudwatch_logs_exports = var.free_tier_account ? [] : ["postgresql"]

  # Oyrenme ucun: destroy-u asanlasdirir. Prod-da tersi olmalidir!
  skip_final_snapshot = true
  deletion_protection = false

  apply_immediately = true

  tags = { Name = "${var.project}-postgres" }
}
