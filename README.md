# Spring Boot + Postgres → ECS Fargate + ALB (Terraform)

## Arxitektura

```
Internet
   │
   ▼
 ALB  (public subnets, SG: 80 ← 0.0.0.0/0; 443 şərh içindədir, ACM sertifikatı olanda açılır)
   │  target group, health check → /actuator/health
   │  listener rule: /actuator/* → 404  (yalnız health endpoint keçir)
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
| `alb.tf` | load balancer, target group, listener, actuator qoruması |
| `iam.tf` | execution role + task role |
| `ecs.tf` | cluster, task definition, service, autoscaling |
| `outputs.tf` | URL-lər, push/redeploy əmrləri |
| `.gitignore` | state və `terraform.tfvars` git-ə düşməsin |

Tətbiq tərəfi ayrı repodadır — nüsxə saxlamırıq ki, ikisi bir-birindən ayrı düşməsin:

| Fayl | Nə var |
|---|---|
| `../test-backend/Dockerfile` | multi-stage Gradle build (Java 17) |
| `../test-backend/src/main/resources/application-prod.yml` | ECS-də oxunan konfiqurasiya |
| `../test-backend/docker-compose.yml` | lokal Postgres |

## `test-backend` ilə müqavilə

Bu iki repo bir-birinə **environment variable adları** ilə bağlıdır. Adlardan biri dəyişsə deploy səssizcə sınır, ona görə hər ikisini eyni anda redaktə et.

| Dəyişən | Kim verir | Kim oxuyur |
|---|---|---|
| `SPRING_PROFILES_ACTIVE=prod` | `ecs.tf` | `application-prod.yml` faylını aktivləşdirir |
| `SPRING_DATASOURCE_URL` | `ecs.tf` (RDS endpoint-dən) | `application-prod.yml` |
| `SPRING_DATASOURCE_USERNAME` | Secrets Manager | `application-prod.yml` |
| `SPRING_DATASOURCE_PASSWORD` | Secrets Manager | `application-prod.yml` |
| `SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE` | `ecs.tf` (10) | `application-prod.yml` |
| `SERVER_PORT` | `ecs.tf` (`container_port`) | `application-prod.yml` |
| `MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE` | `ecs.tf` | `application-prod.yml` |
| `CORS_ALLOWED_ORIGINS` | `ecs.tf` (`cors_allowed_origins`) | `CorsConfig.java` |
| `JAVA_TOOL_OPTIONS` | `ecs.tf` | JVM |

Diqqət yetiriləsi məqamlar:

- **`application-prod.yml` `SPRING_DATASOURCE_URL`-i default-suz oxuyur** (`${SPRING_DATASOURCE_URL}`). Dəyər gəlməsə tətbiq açılışda düşür — səssiz `localhost`-a qoşulmaqdansa bu daha yaxşıdır.
- **`prod` profili məcburidir.** `application.yml` lokal default-ları saxlayır, ECS-də isə `application-prod.yml` onu üstələyir.
- **ECR repo adı = `var.project` = `test-backend`** — Gradle `rootProject.name` ilə eynidir, təsadüfi deyil.
- **Java 17** (`build.gradle` toolchain) ↔ `eclipse-temurin:17` (Dockerfile). `task_memory = 1024` MiB, `MaxRAMPercentage=75` → ~768 MB heap.

## Deploy sırası

⚠️ **ECR boş olarsa ECS task işə düşməyəcək.** Ona görə iki mərhələdə:

```bash
cp terraform.tfvars.example terraform.tfvars   # dəyərləri redaktə et

terraform init
terraform validate
```

### 0) Ön yoxlama — Postgres versiyası

RDS köhnə minor versiyaları region-dan silir. `db_engine_version = "16"` yazılıbsa
AWS ən son minor-u özü seçir və problem olmur. Konkret minor yazacaqsansa əvvəl yoxla:

```bash
aws rds describe-db-engine-versions --engine postgres --region eu-north-1 \
  --query "DBEngineVersions[?starts_with(EngineVersion,'16.')].EngineVersion" --output text
```

Mövcud olmayan versiya `Cannot find version 16.x for postgres` xətası verir —
özü də RDS yaradılan anda, yəni digər resurslar artıq qurulandan sonra.

### 1) Əvvəl yalnız ECR yarat

```bash
terraform apply -target=aws_ecr_repository.app
```

### 2) Image-i push et

```bash
terraform output -raw docker_push_commands
```

Əmrləri **`../test-backend` qovluğunda** işlət (Dockerfile oradadır):

```bash
cd ../test-backend

aws ecr get-login-password --region eu-north-1 \
  | docker login --username AWS --password-stdin <account>.dkr.ecr.eu-north-1.amazonaws.com

docker build --platform linux/amd64 -t <account>.dkr.ecr.eu-north-1.amazonaws.com/test-backend:v1.0.0 .
docker push <account>.dkr.ecr.eu-north-1.amazonaws.com/test-backend:v1.0.0

cd ../deploy-eks
```

`--platform` vacibdir — ARM maşında bu olmasa task `exec format error` ilə düşür.
`image_tag` `terraform.tfvars`-dakı dəyərlə **eyni** olmalıdır (`v1.0.0`).

### 3) Qalan hər şeyi qur

```bash
terraform apply          # RDS ~10 dəqiqə çəkir

terraform output app_url
terraform output -raw logs_command      # loqları izlə
```

### Sonrakı deploy-lar

Service-də `lifecycle { ignore_changes = [task_definition] }` var — bu, CI/CD-nin
qoyduğu image-i Terraform-un geri qaytarmaması üçündür. Nəticədə **yeni image push
edib `terraform apply` etsən service yenilənməyəcək.** Rollout-u əl ilə başlat:

```bash
terraform output -raw redeploy_command
```

### Silmək

```bash
terraform destroy
```

`force_delete`, `skip_final_snapshot`, `recovery_window_in_days = 0` təyin olunduğu üçün
destroy təmiz keçir. Yalnız RDS-in `/aws/rds/instance/.../postgresql` log qrupu qalır —
onu əl ilə sil.

## Postgres-i necə nəzərə aldıq — vacib məqamlar

**1. Parol heç yerdə açıq deyil.**
`random_password` → Secrets Manager → task definition-ın `secrets` bloku. Container-in içində normal environment variable kimi görünür, amma ECS konsolunda və Terraform kodunda görünmür. *Amma parol Terraform state-də açıq mətn kimi saxlanılır* — `.gitignore` `*.tfstate`-i bağlayır, real layihədə isə `versions.tf`-dəki şifrəli S3 backend-i aç.

**2. JDBC URL-də parol yoxdur.**
URL environment, user/password isə secrets kimi ayrı gedir. Belə olanda parol xüsusi simvol saxlaya bilir və URL encoding problemi çıxmır.

**3. Baza internetdən əlçatan deyil.**
`publicly_accessible = false`, private subnet, security group yalnız ECS SG-ni qəbul edir. Lokaldan qoşulmaq üçün bastion host və ya SSM port forwarding lazımdır.

**4. Health check grace period = 120s.**
Bu olmasa Spring Boot açılmağa macal tapmadan ALB onu `unhealthy` sayır, ECS task-ı öldürür və sonsuz restart dövrəsi yaranır. **Fargate-də Spring Boot deploy edənlərin ən çox ilişdiyi yer budur.**

Eyni dövrənin ikinci mənbəyi container-in **öz** `healthCheck`-idir: o, `curl`-u container-in içində işlədir, `eclipse-temurin` və distroless image-lərdə isə curl yoxdur → `exit 127` → hər dəfə unhealthy. Ona görə `enable_container_healthcheck` default `false`-dur; ALB target group health check onsuz da bu işi görür. Image-də curl varsa (bax `Dockerfile.example`) `true` et.

**4a. `/actuator/health` bazadan asılıdır.**
Spring Boot bu endpoint-ə DataSource health indicator-unu da qatır. RDS bir anlıq əlçatmaz olsa (məsələn bazar günü maintenance window-da) **bütün** task-lar eyni anda unhealthy olur və ECS hamısını öldürür — kiçik problem tam kəsintiyə çevrilir. Daha davamlısı:

```hcl
health_check_path = "/actuator/health/liveness"
```

Bunun üçün app tərəfdə `management.endpoint.health.probes.enabled: true` lazımdır — `application-prod.yml.example`-də açıqdır.

**5. JVM container limitini görməlidir.**
`-XX:MaxRAMPercentage=75`. Bu olmasa JVM heap-i host yaddaşına görə hesablayır, limiti aşır və task `OOMKilled` olur — loqda heç bir izahat qalmadan.

**6. HikariCP pool ölçüsü × task sayı ≤ RDS max_connections.**
`db.t4g.micro`-da `max_connections` ≈ 100. Pool 10, autoscaling max 8 task → 80. Sərhəddədir. Task sayını artırırsansa ya pool-u azalt, ya instance-ı böyüt.

**7. Schema — `test-backend`-də Flyway YOXDUR.**
Tətbiq `ddl-auto: update` ilə işləyir, yəni `message` cədvəlini Hibernate özü qurur. RDS boş yaradıldığı üçün bu **məcburidir**: `validate` qoysan tətbiq `missing table [message]` ilə heç açılmayacaq.

2 task eyni anda qalxanda ikisi də `CREATE TABLE` çağırır — biri udur, ikincisi `relation already exists` xəbərdarlığı yazıb davam edir, startup düşmür. Yəni işləyir, amma bu bir test servisinin həlli.

Real prod üçün doğru yol: `build.gradle`-a `implementation 'org.flywaydb:flyway-database-postgresql'` əlavə et, `V1__create_message.sql` yaz, sonra `ddl-auto: validate` et. Flyway advisory lock tutduğu üçün paralel task-larda migration yalnız bir dəfə işləyir.

**8. Graceful shutdown.**
`server.shutdown: graceful` + `stopTimeout: 30` + `deregistration_delay: 30`. Deploy zamanı yarımçıq qalan sorğu olmasın. Dockerfile-da `ENTRYPOINT` **exec formasında** olmalıdır (`["java","-jar",...]`) — shell forması olsa JVM PID 1 olmur və SIGTERM-i almır.

**9. Actuator internetə açıq qalmasın.**
`MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE` `metrics` və `prometheus`-u da açır, ALB isə bütün path-ləri ötürür — yəni `/actuator/prometheus` 0.0.0.0/0-dan görünərdi. `alb.tf`-də iki listener rule var: `/actuator/health` keçir (priority 10), qalan `/actuator/*` 404 alır (priority 20). Target group-un öz health check-i listener rule-lardan keçmir, ona görə bu heç nəyi pozmur.

**10. Docker image arxitekturası.**
`cpu_architecture` (`X86_64` default) ilə `docker build --platform` üst-üstə düşməlidir. `ARM64` seçsən Fargate ~20% ucuzdur, amma image də ARM olmalıdır.

## Xərc (təxmini, eu-north-1)

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
| container `healthCheck` (opsional) | `livenessProbe` |
| ALB target group health check | `readinessProbe` |
| `deployment_circuit_breaker` | Argo Rollouts / manual `kubectl rollout undo` |
| `aws_iam_role.ecs_task` | ServiceAccount + IRSA |
| `enable_execute_command` | `kubectl exec` |

Bunu bir dəfə işə salandan sonra eyni tətbiqi EKS-ə köçürsən, hər sətrin nəyə cavab verdiyini artıq biləcəksən.

## Növbəti addımlar

1. **HTTPS** — Route53 + ACM sertifikat, `alb.tf`-də şərh açılmış hissə hazırdır
2. **CI/CD** — GitHub Actions: build → ECR push → `aws ecs update-service --force-new-deployment`
3. **Frontend** — statik React üçün ayrıca S3 + CloudFront (Fargate-ə salma)
4. **Müşahidə** — `/actuator/prometheus` → Amazon Managed Prometheus və ya CloudWatch metric filter. Scrape kənardan gələcəksə `alb.tf`-dəki `actuator_block` qaydasına `source_ip` şərti əlavə et, qaydanı tamam silmə
5. **VPC Endpoints** — NAT əvəzinə ECR/Secrets/Logs üçün interface endpoint-lər (çox trafikdə daha ucuz)
