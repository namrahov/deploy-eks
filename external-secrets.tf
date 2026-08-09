# ============================================================
# RDS parolunu Secrets Manager-den k8s Secret-e sinxronlasdirir.
# Beleliklede parol nə manifest-de, ne git-de, ne de Terraform
# output-unda acig gorunmur.
#
# ECS-de bunu task definition "secrets" bloku edirdi.
# k8s-de bu isi External Secrets Operator gorur.
# ============================================================

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.10.5"

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

# ---------- Pod Identity: IRSA-nin varisi ----------
# IRSA-dan ferqli olaraq OIDC provider, trust policy JSON-u ve
# annotation lazim deyil. Sadece rol + association.

resource "aws_iam_role" "external_secrets" {
  name = "${var.project}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "read-db-secret"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [aws_secretsmanager_secret.db.arn]
    }]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}

# ---------- Tetbiqin oz IAM rolu ----------
# Spring Boot koddan S3/SQS/SNS-e murachiet edecekse icazeler buraya.
# ECS-deki "task role"-un tam analoqu.

resource "aws_iam_role" "backend" {
  name = "${var.project}-backend"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "backend" {
  cluster_name    = module.eks.cluster_name
  namespace       = "app"
  service_account = "backend"
  role_arn        = aws_iam_role.backend.arn
}
