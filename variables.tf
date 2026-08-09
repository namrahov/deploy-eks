variable "project" {
  # DIQQET: bu ad Secrets Manager secret-inin adina girir
  # ("<project>/db-credentials") ve 01-external-secret.yaml-da ELLE yazilib.
  # Deyisdirsen hemin faylda remoteRef.key-leri de deyis, yoxsa
  # ExternalSecret "SecretSyncedError" verir ve backend pod-lari acilmir.
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
  description = "EKS bir defede yalniz 1 minor versiya yuxari qalxir. Bleeding edge secme."
  type        = string
  default     = "1.34"
}

variable "use_auto_mode" {
  description = <<-EOT
    true  -> EKS Auto Mode. AWS node-lari, Karpenter-i, VPC CNI, EBS CSI,
             CoreDNS ve ALB controller-i ozu idare edir. Tovsiye olunan.
    false -> Klassik managed node group. Ogrenmek ucun faydali,
             amma addon-lari ozun qurmalisan.
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
  # Yalniz major versiya yazilir: RDS hemin major-un en son minor-unu secir.
  # "16.4" kimi deqiq minor yazsan, AWS onu deprecate edende apply xeta verir.
  type    = string
  default = "16"
}

variable "db_performance_insights" {
  description = <<-EOT
    Performance Insights kicik instance-larda DESTEKLENMIR:
    db.t2/t3/t4g .micro ve .small. db.t4g.micro-da true etsen apply
    "InvalidParameterCombination" ile dusur.
    db.t4g.medium ve yuxari kecende true et.
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
