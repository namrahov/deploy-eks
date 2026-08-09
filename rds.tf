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
#
# DIQQET - SG description-lari ucun AWS-in oz simvol siyahisi var:
#   ^[0-9A-Za-z_ .:/()#,@\[\]+=&;{}!$*-]*$
# Yeni ox "->" YAZMA: `<` ve `>` bu siyahida YOXDUR ve apply
#   "doesn't comply with restrictions" ile dusur.
# Eyni sey `_` ve `-` ucun problem deyil, ancaq oxu sozle yaz: "to".

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Yalniz EKS node-larindan Postgres"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "EKS nodes to Postgres"
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

  allocated_storage = var.db_allocated_storage
  # Free tier planinda saxlama 20 GB ile mehduddur -> autoscaling sonduruk (0 = sonulu)
  max_allocated_storage = var.free_tier_account ? 0 : 100
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

  # Free tier hesab avtomatik backup-a icaze vermir:
  #   FreeTierRestrictionError: The specified backup retention period exceeds
  #   the maximum available to free tier customers.
  # 0 = avtomatik backup sondurulub (point-in-time recovery YOXDUR).
  backup_retention_period = var.free_tier_account ? 0 : var.db_backup_retention_period
  backup_window           = var.free_tier_account ? null : "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Performance Insights IKI ayri sebebden bloklana biler:
  #   1) free tier plani, 2) kicik instance class (db.t4g.micro/small).
  # Ona gore hem bayraq, hem de plan yoxlanilir.
  performance_insights_enabled    = var.db_performance_insights && !var.free_tier_account
  enabled_cloudwatch_logs_exports = var.free_tier_account ? [] : ["postgresql"]

  skip_final_snapshot = true  # prod-da false
  deletion_protection = false # prod-da true
  apply_immediately   = true

  tags = { Name = "${var.project}-postgres" }
}
