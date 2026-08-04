output "app_url" {
  description = "Tetbiqin URL-i"
  value       = "http://${aws_lb.main.dns_name}"
}

output "health_url" {
  value = "http://${aws_lb.main.dns_name}${var.health_check_path}"
}

output "ecr_repository_url" {
  description = "docker push bu adrese"
  value       = aws_ecr_repository.app.repository_url
}

output "docker_push_commands" {
  description = "Image-i ECR-e gonderme adimlari"
  value = <<-EOT
    aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.app.repository_url)[0]}
    docker build -t ${var.project} .
    docker tag ${var.project}:latest ${aws_ecr_repository.app.repository_url}:${var.image_tag}
    docker push ${aws_ecr_repository.app.repository_url}:${var.image_tag}
  EOT
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_name" {
  description = "Parolu oxumaq: aws secretsmanager get-secret-value --secret-id <bu>"
  value       = aws_secretsmanager_secret.db.name
}

output "logs_command" {
  value = "aws logs tail ${aws_cloudwatch_log_group.app.name} --follow --region ${var.region}"
}

output "ecs_exec_command" {
  description = "Isleyen container-e girmek (kubectl exec analoqu)"
  value       = "aws ecs execute-command --cluster ${aws_ecs_cluster.main.name} --task <TASK_ID> --container app --interactive --command /bin/sh"
}
