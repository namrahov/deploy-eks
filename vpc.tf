data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets   = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  database_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 8, i + 20)]

  create_database_subnet_group = true

  enable_nat_gateway = true
  single_nat_gateway = true # 1 NAT is enough for learning (~$35/month). Use false in prod.

  enable_dns_hostnames = true
  enable_dns_support   = true

  # ================================================================
  # THESE TAGS ARE MANDATORY FOR EKS
  # Without them the ALB/NLB controller CANNOT FIND the subnets and
  # creating an Ingress fails with "unable to discover subnets".
  # This is the most common place people get stuck on EKS.
  # ================================================================
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1" # internet-facing load balancer
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1" # internal load balancer + nodes
  }
}
