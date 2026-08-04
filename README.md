# Spring Boot + Postgres → ECS Fargate + ALB (Terraform)

## Arxitektura

```
Internet
   │
   ▼
 ALB  (public subnets, SG: 80/443 ← 0.0.0.0/0)
   │  target group, health check → /actuator/health
   ▼
 ECS Service (Fargate)  ── 2..8 task, autoscaling CPU 70%
   │  SG: 8080 ← yalnız ALB SG
   ▼
 RDS Postgres  (private subnets, SG: 5432 ← yalnız ECS SG, publicly_accessible = false)

 ECR ← docker image
 Secrets Manager → DB user/password (task-a runtime-da injeksiya olunur)
 CloudWatch Logs ← stdout
```

## Fayllar

| Fayl | Nə var |
|---|---|
| `versions.tf` | provider, state backend nümunəsi |
| `variables.tf` | bütün parametrlər |
| `vpc.tf` | VPC, 2 public + 2 private subnet, IGW, opsional NAT |
| `security_groups.tf` | ALB → ECS → RDS zənciri |
| `ecr.tf` | docker registry + lifecycle policy |
| `rds.tf` | Postgres, random parol, Secrets Manager |
| `alb.tf` | load balancer, target group, listener |
| `iam.tf` | execution role + task role |
| `ecs.tf` | cluster, task definition, service, autoscaling |
| `outputs.tf` | URL-lər, push əmrləri |
| `Dockerfile.example` | multi-stage Spring Boot build |
| `application-prod.yml.example` | Spring tərəfindəki konfiqurasiya |

## Deploy sırası

⚠️ **ECR boş olarsa ECS task işə düşməyəcək.** Ona görə iki mərhələdə:

```bash
cp terraform.tfvars.example terraform.tfvars   # dəyərləri redaktə et

terraform init

# 1) Əvvəl yalnız ECR yarat
terraform apply -target=aws_ecr_repository.app

# 2) Image-i push et (əmrləri output verir)
terraform output -raw docker_push_commands

# 3) Qalan hər şeyi qur (RDS ~10 dəqiqə çəkir)
terraform apply

terraform output app_url
```

## Postgres-i necə nəzərə aldıq — vacib məqamlar

**1. Parol heç yerdə açıq deyil.**
`random_password` → Secrets Manager → task definition-ın `secrets` bloku. Container-in içində normal environment variable kimi görünür, amma ECS konsolunda və Terraform kodunda görünmür. *Amma parol Terraform state-də saxlanılır* — state-i mütləq şifrəli S3 backend-də saxla, git-ə commit etmə.

**2. JDBC URL-də parol yoxdur.**
URL environment, user/password isə secrets kimi ayrı gedir. Belə olanda parol xüsusi simvol saxlaya bilir və URL encoding problemi çıxmır.

**3. Baza internetdən əlçatan deyil.**
`publicly_accessible = false`, private subnet, security group yalnız ECS SG-ni qəbul edir. Lokaldan qoşulmaq üçün bastion host və ya SSM port forwarding lazımdır.

**4. Health check grace period = 120s.**
Bu olmasa Spring Boot açılmağa macal tapmadan ALB onu `unhealthy` sayır, ECS task-ı öldürür və sonsuz restart dövrəsi yaranır. **Fargate-də Spring Boot deploy edənlərin ən çox ilişdiyi yer budur.**

**5. JVM container limitini görməlidir.**
`-XX:MaxRAMPercentage=75`. Bu olmasa JVM heap-i host yaddaşına görə hesablayır, limiti aşır və task `OOMKilled` olur — loqda heç bir izahat qalmadan.

**6. HikariCP pool ölçüsü × task sayı ≤ RDS max_connections.**
`db.t4g.micro`-da `max_connections` ≈ 100. Pool 10, autoscaling max 8 task → 80. Sərhəddədir. Task sayını artırırsansa ya pool-u azalt, ya instance-ı böyüt.

**7. Flyway migration-lar.**
Bir neçə task eyni anda açılsa da Flyway advisory lock istifadə edir, migration yalnız bir dəfə işləyir. `ddl-auto: validate` — prod-da `update` yazmaq schema-nı gözlənilməz şəkildə dəyişə bilər.

**8. Graceful shutdown.**
`server.shutdown: graceful` + `stopTimeout: 30` + `deregistration_delay: 30`. Deploy zamanı yarımçıq qalan sorğu olmasın.

## Xərc (təxmini, eu-central-1)

| Resurs | ~$/ay |
|---|---|
| ALB | 18 |
| Fargate 2× (0.5 vCPU / 1 GB) | 36 |
| RDS db.t4g.micro + 20 GB gp3 | 17 |
| NAT Gateway (`enable_nat_gateway = true`) | 35 |
| Secrets Manager, ECR, Logs | ~2 |
| **Cəmi (NAT-sız)** | **~73** |

Öyrənmə üçün: `enable_nat_gateway = false`, `desired_count = 1`, `db_multi_az = false`. İşin bitəndə `terraform destroy` — vacibdir.

## k8s ilə müqayisə (bu koda baxaraq)

| Bu koddakı | Kubernetes qarşılığı |
|---|---|
| `aws_ecs_task_definition` | Pod template + container spec |
| `aws_ecs_service` | Deployment |
| `desired_count` | `replicas` |
| `aws_appautoscaling_policy` | HorizontalPodAutoscaler |
| `secrets` bloku | Secret + `envFrom`/`secretKeyRef` |
| `environment` bloku | ConfigMap |
| `aws_lb_target_group` + listener | Ingress + Service |
| `health_check_grace_period_seconds` | `startupProbe` / `initialDelaySeconds` |
| container `healthCheck` | `livenessProbe` |
| ALB target group health check | `readinessProbe` |
| `deployment_circuit_breaker` | Argo Rollouts / manual `kubectl rollout undo` |
| `aws_iam_role.ecs_task` | ServiceAccount + IRSA |
| `enable_execute_command` | `kubectl exec` |

Bunu bir dəfə işə salandan sonra eyni tətbiqi EKS-ə köçürsən, hər sətrin nəyə cavab verdiyini artıq biləcəksən.

## Növbəti addımlar

1. **HTTPS** — Route53 + ACM sertifikat, `alb.tf`-də şərh açılmış hissə hazırdır
2. **CI/CD** — GitHub Actions: build → ECR push → `aws ecs update-service --force-new-deployment`
3. **Frontend** — statik React üçün ayrıca S3 + CloudFront (Fargate-ə salma)
4. **Müşahidə** — `/actuator/prometheus` → Amazon Managed Prometheus və ya CloudWatch metric filter
5. **VPC Endpoints** — NAT əvəzinə ECR/Secrets/Logs üçün interface endpoint-lər (çox trafikdə daha ucuz)
