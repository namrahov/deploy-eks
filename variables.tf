variable "project" {
  description = "Resurs adlarinda prefiks kimi istifade olunur"
  type        = string
  default     = "test-backend"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# ---------- Application ----------

variable "container_port" {
  description = "Spring Boot server.port"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "ALB bu endpoint-i yoxlayacaq. Actuator lazimdir."
  type        = string
  default     = "/actuator/health"
}

variable "image_tag" {
  description = "ECR-de docker image tag-i"
  type        = string
  default     = "latest"
}

variable "spring_profile" {
  type    = string
  default = "prod"
}

variable "cors_allowed_origins" {
  description = <<-EOT
    test-backend-deki app.cors.allowed-origins (CorsConfig.java /api/** ucun).
    Vergulle ayrilmis siyahi: "https://app.example.com,https://admin.example.com".
    Bos qoysan tetbiq oz default-una (http://localhost:5173) qayidir ki,
    prod-da frontend-i bloklayar. Frontend yoxdursa ferqi yoxdur.
  EOT
  type        = string
  default     = "http://localhost:5173"
}

variable "task_cpu" {
  description = "Fargate CPU units (256/512/1024/2048/4096)"
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = <<-EOT
    Task-in arxitekturasi: X86_64 ve ya ARM64.
    Docker image EYNI arxitektura ucun qurulmalidir, yoxsa task
    "exec format error" ile dusur (Apple Silicon-da en cox rast gelinen sehv).
  EOT
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture yalniz X86_64 ve ya ARM64 ola biler."
  }
}

variable "enable_container_healthcheck" {
  description = <<-EOT
    Container-in oz healthCheck-i (ALB-dekinden ayridir).
    DIQQET: `curl` image-in icinde OLMALIDIR. Standart eclipse-temurin /
    distroless image-lerde curl yoxdur -> health check hemise ugursuz olur,
    ECS task-i oldurur ve sonsuz restart dovresi yaranir.
    Dockerfile-da curl qurmusansa true et.
  EOT
  type        = bool
  default     = false
}

variable "task_memory" {
  description = "MiB. JVM ucun 512 azdir, 1024-den baslamaq meslehetdir."
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Nece task isleyecek"
  type        = number
  default     = 2
}

# ---------- Database ----------

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_engine_version" {
  description = <<-EOT
    Yalniz major versiya yaz ("16") -> RDS hemin major-in en son minor-unu secir.
    Konkret minor ("16.14") yazsan, hemin minor regionda MOVCUD olmalidir,
    yoxsa apply "Cannot find version ... for postgres" ile dusur.
    Yoxlamaq: aws rds describe-db-engine-versions --engine postgres --region <region> \
      --query "DBEngineVersions[].EngineVersion"
  EOT
  type        = string
  default     = "16"
}

variable "db_multi_az" {
  description = "Prod-da true. Test ucun false (2 defe ucuz)."
  type        = bool
  default     = false
}

# ---------- Cost / network ----------

variable "enable_nat_gateway" {
  description = <<-EOT
    true  -> ECS task-lar private subnet-de, xarice NAT Gateway vasitesile cixir (~$35/ay).
    false -> ECS task-lar public subnet-de, public IP ile (pulsuz, oyrenme ucun kifayet).
    RDS her iki halda private subnet-de qalir ve xaricden elcatan deyil.
  EOT
  type        = bool
  default     = false
}
