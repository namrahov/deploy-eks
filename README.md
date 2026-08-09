# Frontend + Spring Boot + RDS Postgres → EKS

## Əvvəlcə: 4 yerdə fərqli təklifim var

### 1. Frontend-i EKS-ə salma (statikdirsə)

Bu ən vacib məsləhətdir. React/Vue build çıxışı sadəcə fayldır. Onu pod-da nginx ilə paylamaq üçün ödəyəcəyin qiymət:

- 2 pod × yaddaş/CPU — daimi
- ALB target group, health check, deploy pipeline
- nginx image-inin CVE yamaqları — sənin məsuliyyətin
- CDN yoxdur → Bakıdan da, Berlindən də eyni tək region-a gedilir

S3 + CloudFront-da: ~$1/ay, global CDN, yamaq yoxdur, `aws s3 sync` ilə deploy.

`k8s/03-frontend.yaml` yenə də daxildədir — **öyrənmək üçün**. Kubernetes-də Deployment/Service/ConfigMap/volume mount necə işləyir, bunu görmək dəyərlidir. Amma prod-da CloudFront-a keç.

**İstisna:** Next.js/Nuxt kimi SSR-dırsa, o artıq server prosesidir — həqiqətən EKS-də olmalıdır.

### 2. Managed node group əvəzinə EKS Auto Mode

<cite index="8-1">AWS 2024-cü ilin dekabrında EKS Auto Mode-u elan etdi — compute, storage və şəbəkə idarəçiliyini tam avtomatlaşdıran rejim.</cite> <cite index="6-1">Praktikada bu o deməkdir ki, Karpenter, VPC CNI, EBS CSI, CoreDNS və kube-proxy AWS tərəfindən idarə olunur; nə node group konfiqurasiya edirsən, nə də addon quraşdırırsan.</cite>

<cite index="2-1">Node həyat dövrünü Karpenter idarə edir: gözləyən pod-lar üçün ölçüsü uyğun instance yaradır, az istifadə olunan node-ları birləşdirib xərci azaldır.</cite>

Sənin üçün nə dəyişir: AMI yeniləmələri, node drain, cluster-autoscaler tənzimləmə, addon versiya uyğunluğu — bunların heç biri sənin işin deyil. `var.use_auto_mode = false` etsən klassik node group qurulur (daxili mexanizmi görmək üçün faydalıdır).

**Nə vaxt Auto Mode uyğun gəlmir:** node-a özəl AMI, DaemonSet-lə aşağı səviyyəli agent, spesifik kernel parametrləri lazımdırsa.

### 3. IRSA əvəzinə EKS Pod Identity

IRSA-da OIDC provider, JSON trust policy və ServiceAccount annotation-u lazım idi. Pod Identity-də sadəcə rol yaradırsan və association ilə namespace/ServiceAccount cütünə bağlayırsan. Kodda müqayisə üçün hər ikisinin fərqi `external-secrets.tf`-də şərh edilib.

### 4. Manifestləri Terraform-la idarə etmə

Terraform **infrastruktur** üçündür: VPC, EKS, RDS, IAM. Tətbiq manifestləri üçün `kubernetes_manifest` resursu istifadə etmə — Terraform CRD-ləri plan mərhələsində bilmir, `terraform plan` cluster-ə qoşulmağa məcbur olur, və deploy sürəti dəhşətli olur.

Düzgün ayrım:

```
Terraform  →  VPC, EKS, RDS, IAM, ECR, cluster-səviyyə Helm chart-lar
kubectl/Helm/Argo CD  →  Deployment, Service, Ingress, ConfigMap
```

Növbəti addım olaraq **Argo CD** (GitOps) — yol xəritəndə onsuz da var.

---

## Arxitektura

```
Internet
   │
   ▼
 ALB  (Ingress ilə yaradılır, target-type: ip)
   ├── /api/*, /actuator/*  ──► Service backend  ──► Pod (Spring Boot)
   └── /*                   ──► Service frontend ──► Pod (nginx)
                                     │
                        ┌────────────┘
                        ▼
              RDS Postgres (database subnets, private)
                        ▲
                        │ parol
        Secrets Manager ─┴─► External Secrets Operator ──► k8s Secret
```

## Deploy sırası

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # redaktə et

terraform init

# 1) Əvvəl ECR (image-siz pod işə düşməz)
terraform apply -target=aws_ecr_repository.app

# 2) Image-ləri push et
terraform output ecr_login          # çıxan əmri işlət
docker build -t backend ./backend && docker tag ... && docker push ...

# 3) Qalanını qur (EKS ~15 dəq, RDS ~10 dəq — paralel gedir)
terraform apply

# 4) kubectl konfiqurasiyası
$(terraform output -raw configure_kubectl)
kubectl get nodes        # Auto Mode-da pod deploy edənə qədər node görünməyə bilər

# 5) Manifestləri tətbiq et
cd ../k8s
# 01-external-secret.yaml → secret adını və region-u düzəlt
# 02, 03 → <ECR_*_URL> yerinə real URL
kubectl apply -f .

# 6) Yoxla
kubectl get externalsecret -n app        # STATUS: SecretSynced olmalıdır
kubectl get pods -n app -w
kubectl get ingress -n app               # ADDRESS sütunu 2-3 dəq sonra dolur
```

## ECS → k8s: kod səviyyəsində qarşılıq

Əvvəlki layihəni bura köçürərkən nə nəyə çevrildi:

| ECS Fargate | Bu layihədə | Fayl |
|---|---|---|
| Task definition | Deployment `spec.template` | `02-backend.yaml` |
| Service | Deployment | `02-backend.yaml` |
| `desired_count` | `replicas` | `02-backend.yaml` |
| `environment` bloku | ConfigMap + `envFrom` | `02-backend.yaml` |
| `secrets` bloku | ExternalSecret → Secret → `secretKeyRef` | `01-`, `02-` |
| ALB + target group | Ingress + Service | `04-ingress.yaml` |
| `health_check_grace_period_seconds` | `startupProbe` | `02-backend.yaml` |
| container `healthCheck` | `livenessProbe` | `02-backend.yaml` |
| TG health check | `readinessProbe` | `02-backend.yaml` |
| `aws_appautoscaling_policy` | HorizontalPodAutoscaler | `02-backend.yaml` |
| ECS task role | Pod Identity + ServiceAccount | `external-secrets.tf` |
| `deployment_circuit_breaker` | `kubectl rollout undo` / Argo Rollouts | — |
| `enable_execute_command` | `kubectl exec` | — |
| SG-lər arası zəncir | NetworkPolicy | `05-networkpolicy.yaml` |
| (yoxdur) | PodDisruptionBudget | `02-backend.yaml` |
| (yoxdur) | topologySpreadConstraints | `02-backend.yaml` |

Son iki sətir k8s-in ECS üzərində real üstünlüyüdür — node yenilənərkən nə qədər pod-un yıxıla biləcəyini və pod-ların AZ-lər arasında necə yayılacağını dəqiq idarə edirsən.

## Spring Boot üçün kritik məqamlar

**1. Üç probe, üç ayrı iş.** ECS-də bir health check var idi, burada üç var:

- `startupProbe` — "hələ açılır, öldürmə". **Bu olmasa liveness Spring-i açılmağa macal tapmadan öldürür və sonsuz restart dövrəsi yaranır.** Fargate-dəki `health_check_grace_period_seconds`-in analoqu.
- `readinessProbe` — "trafik göndərə bilərsən?". `false` olanda pod Service endpoint-lərindən çıxarılır, amma restart olmur.
- `livenessProbe` — "asılıb qalıb?". `false` olanda pod restart olur.

Spring Boot-da `management.endpoint.health.probes.enabled: true` yazsan `/actuator/health/liveness` və `/readiness` ayrıca açılır. Readiness Flyway migration bitənə qədər `DOWN` qalır — məhz istədiyimiz davranışdır.

**2. `requests` vs `limits`.** Scheduler `requests`-ə görə node seçir, `limits` aşılanda pod öldürülür. CPU limit-i **qoyma** — JVM-də GC thread-ləri throttle olunur və latency partlayır. Memory limit-i qoy.

**3. `-XX:MaxRAMPercentage=75`.** ECS-də olduğu kimi. Bu olmasa JVM node yaddaşına görə heap hesablayır və `OOMKilled` olur.

**4. `maxUnavailable: 0`.** Deploy zamanı əvvəl yeni pod ready olur, sonra köhnəsi silinir.

**5. HikariCP × replica ≤ RDS `max_connections`.** `db.t4g.micro`-da ~100. Pool 10 × HPA max 8 = 80. Sərhəddədir. Replika artırırsansa ya pool azalt, ya instance böyüt. **Bu k8s-də ECS-dən daha təhlükəlidir**, çünki HPA səni xəbərsiz 8 replikaya çıxarır.

**6. Subnet tag-ları.** `vpc.tf`-də `kubernetes.io/role/elb` və `internal-elb`. Bunlar olmasa Ingress ALB yarada bilmir və `unable to discover subnets` xətası verir. EKS-də ən çox ilişilən yer budur.

## Xərc (təxmini, eu-central-1)

| Resurs | ~$/ay |
|---|---|
| EKS control plane | 73 |
| Auto Mode compute (2× t3.medium ekvivalenti + Auto Mode əlavəsi) | ~70 |
| ALB | 18 |
| NAT Gateway (single) | 35 |
| RDS db.t4g.micro | 17 |
| **Cəmi** | **~215** |

ECS versiyası ~$73 idi. **Fərqin böyük hissəsi control plane-in $73-üdür — o, sən heç nə deploy etməsən də ödənilir.** İki servis üçün k8s-in iqtisadi cəhətdən niyə ağır olduğunu ilk cavabda deyəndə nəzərdə tutduğum məhz budur. Öyrənmə üçün tamamilə normaldır, sadəcə **işin bitəndə `terraform destroy` et** — unudulmuş EKS cluster-i bahalı dərsdir.

## Növbəti addımlar

1. **Argo CD** — manifestləri git-dən avtomatik sinxronlaşdır (GitOps mərhələsi)
2. **HTTPS** — ACM sertifikat + `04-ingress.yaml`-dakı şərh açılmış annotation-lar
3. **Müşahidə** — Prometheus + Grafana, `/actuator/prometheus` scrape et
4. **Frontend-i CloudFront-a köçür** — pod-ları sil, xərc və gecikmə azalsın
5. **Backup/DR** — Velero ilə cluster state, RDS snapshot siyasəti
