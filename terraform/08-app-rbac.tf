# 3.1 Custom ClusterRole to allow CSI driver to sync secrets across the cluster
resource "kubernetes_cluster_role" "csi_secret_sync_role" {
  metadata {
    name = "csi-secret-sync-cluster-role"
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "create", "update", "patch", "delete", "list", "watch"]
  }

  depends_on = [google_container_cluster.openclaw_cluster]
}

resource "kubernetes_cluster_role_binding" "csi_secret_sync_binding" {
  metadata {
    name = "csi-secret-sync-cluster-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.csi_secret_sync_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "secrets-store-csi-driver-gke"
    namespace = "kube-system"
  }
}