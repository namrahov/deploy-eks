resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/db-credentials"
  recovery_window_in_days = 0 # for learning
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  # These JSON keys are used in k8s/01-external-secret.yaml
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
# Difference from ECS: here the source is the SG of the EKS nodes.
# In Auto Mode the nodes also get the cluster primary SG.
#
# WARNING - AWS has its own character whitelist for SG descriptions:
#   ^[0-9A-Za-z_ .:/()#,@\[\]+=&;{}!$*-]*$
# Do NOT write an arrow "->": `<` and `>` are NOT in that list and apply fails
#   with "doesn't comply with restrictions".
# `_` and `-` are fine, but spell the arrow out as a word: "to".

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Postgres from EKS nodes only"
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
  # On the free tier plan storage is capped at 20 GB, so autoscaling is off (0 = disabled)
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

  # A free tier account does not allow automated backups:
  #   FreeTierRestrictionError: The specified backup retention period exceeds
  #   the maximum available to free tier customers.
  # 0 = automated backups disabled (there is NO point-in-time recovery).
  backup_retention_period = var.free_tier_account ? 0 : var.db_backup_retention_period
  backup_window           = var.free_tier_account ? null : "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Performance Insights can be blocked for TWO separate reasons:
  #   1) the free tier plan, 2) a small instance class (db.t4g.micro/small).
  # That's why both the flag and the plan are checked.
  performance_insights_enabled    = var.db_performance_insights && !var.free_tier_account
  enabled_cloudwatch_logs_exports = var.free_tier_account ? [] : ["postgresql"]

  skip_final_snapshot = true  # false in prod
  deletion_protection = false # true in prod
  apply_immediately   = true

  tags = { Name = "${var.project}-postgres" }
}
