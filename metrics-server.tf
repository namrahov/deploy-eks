# ============================================================
# metrics-server
#
# EKS Auto Mode CoreDNS, kube-proxy, VPC CNI, EBS CSI ve ALB
# controller-i ozu qurur - AMMA metrics-server-i QURMUR.
#
# O olmasa 02-backend.yaml-daki HorizontalPodAutoscaler islemir:
#   kubectl get hpa -n app
#   TARGETS: <unknown>/70%
# ve pod-lar hec vaxt scale olunmur. `kubectl top` de isləmir.
#
# Klassik node group-da da (use_auto_mode = false) veziyyet eynidir,
# ona gore her iki halda qurulur.
# ============================================================

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.2"

  set {
    name  = "args[0]"
    value = "--kubelet-preferred-address-types=InternalIP"
  }

  depends_on = [module.eks]
}
