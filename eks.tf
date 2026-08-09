module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.project
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Control plane API-si internetden elcatan (oyrenme ucun).
  # Prod-da: endpoint_public_access = false + VPN/bastion, ve ya
  # public_access_cidrs = ["<sizin ofis IP>/32"]
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # terraform apply eden IAM user avtomatik cluster-admin olur.
  # Bu olmasa "error: You must be logged in to the server" alacaqsan.
  enable_cluster_creator_admin_permissions = true

  # aws-auth ConfigMap kohnelib. Indi API-based access entries istifade olunur.
  authentication_mode = "API"

  # ---------- AUTO MODE ----------
  # Node group yoxdur. Karpenter, VPC CNI, CoreDNS, kube-proxy,
  # EBS CSI ve ALB controller AWS terefinden idare olunur.
  #
  # DIQQET: ternary-nin HER IKI terefi EYNI atributlara malik olmalidir.
  # `: {}` yazsan `terraform validate` "Inconsistent conditional result types"
  # verir - cunki bos obyekt {enabled=bool, node_pools=list} tipine uygunlasmir.
  # Ona gore false terefinde de eyni acarlar var, sadece enabled = false.
  cluster_compute_config = var.use_auto_mode ? {
    enabled = true
    # "general-purpose" adi is yuku ucundur.
    # "system" ayrica, CriticalAddonsOnly taint-i ile gelen pool-dur - onu
    # yalniz sistem komponentlerini is yukunden ayirmaq isteyende elave et.
    # (GPU-nun bu siyahi ile elaqesi yoxdur, Auto Mode onu ayrica idare edir.)
    node_pools = ["general-purpose"]
    } : {
    enabled    = false
    node_pools = []
  }

  # ---------- KLASSIK NODE GROUP (use_auto_mode = false olanda) ----------
  eks_managed_node_groups = var.use_auto_mode ? {} : {
    default = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 5
      desired_size   = 2

      # Node-lar avtomatik olaraq AL2023 AMI-nin son versiyasini alir
      ami_type = "AL2023_x86_64_STANDARD"
    }
  }

  # Auto Mode olmayanda addon-lari elle qurmaq lazimdir
  cluster_addons = var.use_auto_mode ? {} : {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
  }

  # Cluster-in oz SG-si. RDS bunu qebul edecek.
  cluster_security_group_additional_rules = {}
}
