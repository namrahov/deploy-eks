# ============================================================
# Syncs the RDS password from Secrets Manager into a k8s Secret.
# This way the password appears in plaintext neither in the manifests,
# nor in git, nor in the Terraform output.
#
# On ECS this was done by the task definition "secrets" block.
# On k8s the External Secrets Operator does the job.
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

# ---------- Pod Identity: the successor to IRSA ----------
# Unlike IRSA, no OIDC provider, trust policy JSON or annotation
# is needed. Just a role + an association.

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

# ---------- The application's own IAM role ----------
# If the Spring Boot code calls S3/SQS/SNS, the permissions go here.
# The exact analogue of the ECS "task role".

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
