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
  single_nat_gateway = true # oyrenme ucun 1 NAT kifayetdir (~$35/ay). Prod-da false.

  enable_dns_hostnames = true
  enable_dns_support   = true

  # ================================================================
  # BU TAG-LAR EKS UCUN MECBURIDIR
  # Bunlar olmasa ALB/NLB controller subnet-leri TAPA BILMIR ve
  # Ingress yaradanda "unable to discover subnets" xetasi verir.
  # EKS-de en cox ilisilen yer buradir.
  # ================================================================
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1" # internet-facing load balancer
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1" # daxili load balancer + node-lar
  }
}
