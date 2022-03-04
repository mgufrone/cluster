module "trust-autoscaler" {
  depends_on = [local_file.kubeconfig]
  source          = "./modules/trust-iam"
  service_account = "cluster-autoscaler"
  namespace       = local.system_namespace
  cluster_name    = local.cluster_name
  oidc_url        = module.eks.cluster_oidc_issuer_url
  source_json     = file("./iam/cluster-autoscaler.json")
  role_name       = "cluster-autoscaler"
}

resource "helm_release" "cluster-autoscaler" {
  chart = "cluster-autoscaler"
  name  = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  namespace = local.system_namespace
  set {
    name  = "autoDiscovery.clusterName"
    value = local.cluster_name
  }
  set {
    name  = "rbac.serviceAccount.create"
    value = "false"
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = module.trust-autoscaler.service_account
  }
  set {
    name  = "awsRegion"
    value = var.region
  }
  values = [
    file("./kube-system/cluster-autoscaler.yaml")
  ]
}
