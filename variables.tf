variable "project" {
  # WARNING: this name goes into the Secrets Manager secret name
  # ("<project>/db-credentials") and is hardcoded in 01-external-secret.yaml.
  # If you change it, change the remoteRef.key values in that file too,
  # otherwise the ExternalSecret reports "SecretSyncedError" and the backend
  # pods never start.
  type    = string
  default = "my-springboot-eks"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS only upgrades one minor version at a time. Don't pick bleeding edge."
  type        = string
  default     = "1.34"
}

variable "use_auto_mode" {
  description = <<-EOT
    true  -> EKS Auto Mode. AWS manages the nodes, Karpenter, VPC CNI, EBS CSI,
             CoreDNS and the ALB controller for you. Recommended.
    false -> Classic managed node group. Useful for learning,
             but you have to install the addons yourself.
  EOT
  type        = bool
  default     = true
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

variable "db_engine_version" {
  # Only the major version is given: RDS picks the latest minor of that major.
  # If you pin an exact minor like "16.4", apply breaks once AWS deprecates it.
  type    = string
  default = "16"
}

variable "free_tier_account" {
  description = <<-EOT
    Accounts on the AWS "Free Tier" plan block a number of RDS features and
    apply fails with `FreeTierRestrictionError`.
    true  -> automated backups, storage autoscaling, CloudWatch log export and
             Performance Insights are disabled.
    false -> everything is enabled (if you moved the account to a paid plan).
    To check: AWS Console -> Billing -> Free tier / Account plan.
  EOT
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Number of days. Only applied when free_tier_account = false."
  type        = number
  default     = 7
}

variable "db_performance_insights" {
  description = <<-EOT
    Performance Insights is NOT SUPPORTED on small instances:
    db.t2/t3/t4g .micro and .small. If you set true on db.t4g.micro, apply
    fails with "InvalidParameterCombination".
    Set it to true once you move to db.t4g.medium or larger.
  EOT
  type        = bool
  default     = false
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}
