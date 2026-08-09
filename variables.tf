variable "project" {
  type    = string
  default = "springboot-eks"
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
  type    = string
  default = "16.4"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}
