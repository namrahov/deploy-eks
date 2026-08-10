module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.project
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # The control plane API is reachable from the internet (for learning).
  # In prod: endpoint_public_access = false + VPN/bastion, or
  # public_access_cidrs = ["<your office IP>/32"]
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # The IAM user running terraform apply automatically becomes cluster-admin.
  # Without this you get "error: You must be logged in to the server".
  enable_cluster_creator_admin_permissions = true

  # The aws-auth ConfigMap is deprecated. API-based access entries are used now.
  authentication_mode = "API"

  # ---------- AUTO MODE ----------
  # No node group. Karpenter, VPC CNI, CoreDNS, kube-proxy,
  # EBS CSI and the ALB controller are managed by AWS.
  #
  # WARNING: BOTH sides of the ternary must have the SAME attributes.
  # If you write `: {}`, `terraform validate` reports "Inconsistent conditional
  # result types" - an empty object does not conform to the
  # {enabled=bool, node_pools=list} type.
  # That's why the false branch has the same keys, just with enabled = false.
  cluster_compute_config = var.use_auto_mode ? {
    enabled = true
    # "general-purpose" is for ordinary workloads.
    # "system" is a separate pool that comes with the CriticalAddonsOnly taint -
    # add it only when you want to isolate system components from the workload.
    # (GPUs have nothing to do with this list, Auto Mode handles them separately.)
    node_pools = ["general-purpose"]
    } : {
    enabled    = false
    node_pools = []
  }

  # ---------- CLASSIC NODE GROUP (when use_auto_mode = false) ----------
  eks_managed_node_groups = var.use_auto_mode ? {} : {
    default = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 5
      desired_size   = 2

      # Nodes automatically get the latest version of the AL2023 AMI
      ami_type = "AL2023_x86_64_STANDARD"
    }
  }

  # Without Auto Mode the addons have to be installed manually
  cluster_addons = var.use_auto_mode ? {} : {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true }
    eks-pod-identity-agent = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
  }

  # The cluster's own SG. RDS will accept traffic from it.
  cluster_security_group_additional_rules = {}
}
