# ============================================================
# metrics-server
#
# EKS Auto Mode installs CoreDNS, kube-proxy, VPC CNI, EBS CSI and the
# ALB controller by itself - BUT it does NOT install metrics-server.
#
# Without it the HorizontalPodAutoscaler in 02-backend.yaml does not work:
#   kubectl get hpa -n app
#   TARGETS: <unknown>/70%
# and pods never scale. `kubectl top` does not work either.
#
# The situation is the same on a classic node group (use_auto_mode = false),
# so it is installed in both cases.
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
