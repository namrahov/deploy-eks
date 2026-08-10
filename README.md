# Frontend + Spring Boot + RDS Postgres → EKS

## First: 4 places where I suggest something different

### 1. Don't put the frontend on EKS (if it's static)

This is the most important advice. A React/Vue build output is just files. The price you pay to serve them from an nginx pod:

- 2 pods × memory/CPU — permanently
- ALB target group, health check, deploy pipeline
- CVE patching of the nginx image — your responsibility
- No CDN → traffic from Baku and from Berlin both hit the same single region

On S3 + CloudFront: ~$1/month, global CDN, no patching, deploy with `aws s3 sync`.

`../test-frontend/03-frontend.yaml` is still included — **for learning**. Seeing how Deployment/Service/ConfigMap/volume mount work in Kubernetes is worth it. But in prod, move to CloudFront.

**Exception:** if it's SSR like Next.js/Nuxt, that's already a server process — it genuinely belongs on EKS.

### 2. EKS Auto Mode instead of a managed node group

<cite index="8-1">In December 2024 AWS announced EKS Auto Mode — a mode that fully automates compute, storage and networking management.</cite> <cite index="6-1">In practice this means Karpenter, VPC CNI, EBS CSI, CoreDNS and kube-proxy are managed by AWS; you neither configure node groups nor install addons.</cite>

<cite index="2-1">Karpenter manages the node lifecycle: it launches right-sized instances for pending pods and consolidates underutilized nodes to cut cost.</cite>

What changes for you: AMI updates, node drain, cluster-autoscaler tuning, addon version compatibility — none of that is your job anymore. Set `var.use_auto_mode = false` and a classic node group is created instead (useful for seeing the internal mechanics).

**When Auto Mode is not a fit:** if you need a custom AMI on the node, a low-level agent as a DaemonSet, or specific kernel parameters.

### 3. EKS Pod Identity instead of IRSA

IRSA required an OIDC provider, a JSON trust policy and a ServiceAccount annotation. With Pod Identity you just create a role and bind it to a namespace/ServiceAccount pair via an association. The difference between the two is commented in `external-secrets.tf` for comparison.

### 4. Don't manage manifests with Terraform

Terraform is for **infrastructure**: VPC, EKS, RDS, IAM. Don't use the `kubernetes_manifest` resource for application manifests — Terraform can't know CRDs at plan time, `terraform plan` is forced to connect to the cluster, and deploy speed becomes terrible.

The right split:

```
Terraform  →  VPC, EKS, RDS, IAM, ECR, cluster-level Helm charts
kubectl/Helm/Argo CD  →  Deployment, Service, Ingress, ConfigMap
```

As a next step: **Argo CD** (GitOps) — it's already on your roadmap anyway.

---

## Architecture

```
Internet
   │
   ▼
 ALB  (created by the Ingress, target-type: ip)
   ├── /api/*  ──► Service backend  ──► Pod (Spring Boot)
   └── /*      ──► Service frontend ──► Pod (nginx)
                                     │
                        ┌────────────┘
                        ▼
              RDS Postgres (database subnets, private)
                        ▲
                        │ password
        Secrets Manager ─┴─► External Secrets Operator ──► k8s Secret
```

## Where the files live

The manifests are **split across three repos** — each application's manifest lives in its own repo:

| File | Repo |
|---|---|
| `*.tf`, `00-namespace.yaml`, `01-external-secret.yaml`, `04-ingress.yaml`, `05-networkpolicy.yaml` | `deploy-eks` (this repo, root directory) |
| `02-backend.yaml` | `../test-backend` |
| `03-frontend.yaml` | `../test-frontend` |

There are **no** separate `terraform/` and `k8s/` directories — the Terraform files are at the root.

## Deploy order

```bash
cp terraform.tfvars.example terraform.tfvars   # edit it
terraform init

# 1) ECR first (a pod can't start without an image)
terraform apply -target=aws_ecr_repository.app

# 2) Push the images
terraform output -raw ecr_login          # run the command it prints (docker login)

BE=$(terraform output -raw ecr_backend_url)
FE=$(terraform output -raw ecr_frontend_url)

cd ../test-backend
docker build --platform linux/amd64 -t $BE:v1.0.0 . && docker push $BE:v1.0.0
sed -i "s|newName: .*|newName: $BE|" kustomization.yaml

cd ../test-frontend
docker build --platform linux/amd64 -t $FE:v1.0.0 . && docker push $FE:v1.0.0
sed -i "s|newName: .*|newName: $FE|" kustomization.yaml

# 3) Build the rest (EKS ~15 min, RDS ~10 min — they run in parallel)
cd ../deploy-eks
terraform apply

# 4) Configure kubectl
$(terraform output -raw configure_kubectl)      # PowerShell: Invoke-Expression (terraform output -raw configure_kubectl)
kubectl get nodes        # in Auto Mode no node may appear until you deploy a pod

# 5) Apply the manifests — ORDER MATTERS
#    01-external-secret.yaml → remoteRef.key must match `terraform output -raw db_secret_name`
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-external-secret.yaml
kubectl apply -k ../test-backend     # -k, NOT -f: kustomize sets the image name
kubectl apply -k ../test-frontend
kubectl apply -f 04-ingress.yaml
kubectl apply -f 05-networkpolicy.yaml

# 6) Verify
kubectl get externalsecret -n app        # STATUS should be SecretSynced
kubectl get pods -n app -w
kubectl get hpa -n app                   # TARGETS must show a percentage, not <unknown>
kubectl get ingress -n app               # the ADDRESS column fills in after 2-3 min
```

`00-namespace.yaml` must go first: without the `backend` ServiceAccount the pod
never starts, failing with `error looking up service account app/backend`.

PowerShell has no `sed` — the equivalent of the two `sed` lines in step 2:

```powershell
$BE = terraform output -raw ecr_backend_url
$FE = terraform output -raw ecr_frontend_url

cd ..\test-backend
docker build --platform linux/amd64 -t "${BE}:v1.0.0" . ; docker push "${BE}:v1.0.0"
(Get-Content kustomization.yaml) -replace 'newName: .*', "newName: $BE" | Set-Content kustomization.yaml -Encoding utf8

cd ..\test-frontend
docker build --platform linux/amd64 -t "${FE}:v1.0.0" . ; docker push "${FE}:v1.0.0"
(Get-Content kustomization.yaml) -replace 'newName: .*', "newName: $FE" | Set-Content kustomization.yaml -Encoding utf8
```

### Why the image name lives in `kustomization.yaml`

`02-backend.yaml` used to contain `image: <ECR_BACKEND_URL>:v1.0.0`. That is **not a valid
image name** (`<` and `>` are not allowed characters), but Kubernetes does not validate the
image string at apply time — `kubectl apply` silently succeeds, and the pod then gets stuck
in `InvalidImageName`. So if you forget to substitute it, you learn about the error from
`kubectl describe pod`, not from `kubectl apply`.

Now the manifest itself is a valid document, and the only account-specific value is
`newName` in `kustomization.yaml`. On top of that: `kustomize` is Argo CD's
(§"Next steps") native input format, so this step makes the move to GitOps cheaper.

**Important:** these two manifests are now applied with `-k`. If you run
`kubectl apply -f 02-backend.yaml`, the image is not substituted and the pod gets `ErrImagePull`.

## ECS → k8s: the mapping at the code level

What turned into what while porting the previous project over here:

| ECS Fargate | In this project | File |
|---|---|---|
| Task definition | Deployment `spec.template` | `02-backend.yaml` |
| Service | Deployment | `02-backend.yaml` |
| `desired_count` | `replicas` | `02-backend.yaml` |
| `environment` block | ConfigMap + `envFrom` | `02-backend.yaml` |
| `secrets` block | ExternalSecret → Secret → `secretKeyRef` | `01-`, `02-` |
| ALB + target group | Ingress + Service | `04-ingress.yaml` |
| `health_check_grace_period_seconds` | `startupProbe` | `02-backend.yaml` |
| container `healthCheck` | `livenessProbe` | `02-backend.yaml` |
| TG health check | `readinessProbe` | `02-backend.yaml` |
| `aws_appautoscaling_policy` | HorizontalPodAutoscaler | `02-backend.yaml` |
| ECS task role | Pod Identity + ServiceAccount | `external-secrets.tf` + `00-namespace.yaml` |
| `deployment_circuit_breaker` | `kubectl rollout undo` / Argo Rollouts | — |
| `enable_execute_command` | `kubectl exec` | — |
| Chain of SGs | NetworkPolicy | `05-networkpolicy.yaml` |
| (none) | PodDisruptionBudget | `02-backend.yaml` |
| (none) | topologySpreadConstraints | `02-backend.yaml` |

The last two rows are k8s's real advantage over ECS — you control precisely how many pods may go down during a node upgrade and how pods spread across AZs.

## Critical points for Spring Boot

**1. Three probes, three separate jobs.** On ECS there was one health check; here there are three:

- `startupProbe` — "still booting, don't kill me". **Without it, liveness kills Spring before it gets a chance to start and you end up in an endless restart loop.** The equivalent of Fargate's `health_check_grace_period_seconds`.
- `readinessProbe` — "can you take traffic?". When `false`, the pod is removed from the Service endpoints but is not restarted.
- `livenessProbe` — "are you hung?". When `false`, the pod is restarted.

In Spring Boot, setting `management.endpoint.health.probes.enabled: true` exposes `/actuator/health/liveness` and `/readiness` separately. Readiness stays `DOWN` until Flyway migration finishes — exactly the behavior we want.

**2. `requests` vs `limits`.** The scheduler picks a node based on `requests`; the pod is killed when `limits` are exceeded. Do **not** set a CPU limit — the JVM's GC threads get throttled and latency explodes. Do set a memory limit.

**3. `-XX:MaxRAMPercentage=75`.** Same as on ECS. Without it the JVM sizes the heap from the node's memory and you get `OOMKilled`.

**4. `maxUnavailable: 0`.** During a deploy, the new pod becomes ready first and only then is the old one removed.

**5. HikariCP × replicas ≤ RDS `max_connections`.** On `db.t4g.micro` that's ~100. Pool 10 × HPA max 8 = 80. That's right at the edge. If you raise replicas, either shrink the pool or grow the instance. **This is more dangerous on k8s than on ECS**, because the HPA scales you to 8 replicas without telling you.

**6. Subnet tags.** `kubernetes.io/role/elb` and `internal-elb` in `vpc.tf`. Without them the Ingress can't create an ALB and fails with `unable to discover subnets`. This is the single most common place people get stuck on EKS.

**7. `/actuator` is not exposed to the internet.** The Ingress only has `/api` and `/` rules.
The `management...exposure.include` list contains `metrics` and `prometheus` — exposing those
through the ALB would hand an outsider your endpoint names, JVM/DB metrics and traffic volume.
The ALB health check lives **at the target group level**, independent of the Ingress rules, so
closing this path does not break the probes.
Prometheus scraping is done from inside the cluster via `Service backend:80/actuator/prometheus`.

**8. The health check path lives on the Service, not the Ingress.** If `alb.ingress.kubernetes.io/healthcheck-path`
is set on the Ingress, it applies to **both** target groups and one of them is guaranteed to fail
its health check (backend `/actuator/health/readiness`, frontend `/healthz`). That's why the
annotation sits on each Service. If the default `/` were left in place, Spring would return 404,
it wouldn't match `success-codes: "200"`, and `/api` would permanently return 503.

**9. metrics-server is not part of Auto Mode.** Auto Mode manages CoreDNS, kube-proxy, VPC CNI,
EBS CSI and the ALB controller, but **not metrics-server**. Without it the HPA shows
`TARGETS: <unknown>/70%` and never scales. `metrics-server.tf` installs it via Helm.

## Cost (approximate, eu-north-1)

| Resource | ~$/month |
|---|---|
| EKS control plane | 73 |
| Auto Mode compute (2× t3.medium equivalent + Auto Mode surcharge) | ~70 |
| ALB | 18 |
| NAT Gateway (single) | 35 |
| RDS db.t4g.micro | 17 |
| **Total** | **~215** |

The ECS version was ~$73. **Most of the difference is the control plane's $73 — you pay it even if you deploy nothing.** This is exactly what I meant in my first answer about why k8s is economically heavy for two services. For learning it's perfectly fine, just **run `terraform destroy` when you're done** — a forgotten EKS cluster is an expensive lesson.

## Next steps

1. **Argo CD** — sync manifests from git automatically (the GitOps stage)
2. **HTTPS** — ACM certificate + uncomment the annotations in `04-ingress.yaml`
3. **Observability** — Prometheus + Grafana, scrape `/actuator/prometheus`
4. **Move the frontend to CloudFront** — delete the pods, cut cost and latency
5. **Backup/DR** — cluster state with Velero, RDS snapshot policy
