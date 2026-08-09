output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "ecr_backend_url" {
  value = aws_ecr_repository.app["backend"].repository_url
}

output "ecr_frontend_url" {
  value = aws_ecr_repository.app["frontend"].repository_url
}

output "ecr_login" {
  value = "aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.app["backend"].repository_url)[0]}"
}

output "db_secret_name" {
  description = "ExternalSecret bu adi istifade edir"
  value       = aws_secretsmanager_secret.db.name
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "get_ingress_url" {
  value = "kubectl get ingress -n app app-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
