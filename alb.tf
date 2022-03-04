module "trust-alb" {
  depends_on = [local_file.kubeconfig]
  source          = "./modules/trust-iam"
  service_account = "aws-load-balancer-controller"
  namespace       = local.system_namespace
  cluster_name    = local.cluster_name
  oidc_url        = module.eks.cluster_oidc_issuer_url
  source_json     = file("./iam/iam-policy.json")
  role_name       = "aws-load-balancer-controller"
}


resource "helm_release" "alb_ingress_controller" {
  depends_on = [null_resource.apply, helm_release.cert-manager]
  repository = "https://aws.github.io/eks-charts"
  chart = "aws-load-balancer-controller"
  name  = "aws-load-balancer-controller"
  namespace = local.system_namespace
  values = [
    file("./kube-system/alb.yaml")
  ]
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "clusterName"
    value = local.cluster_name
  }
  set {
    name  = "serviceAccount.name"
    value = module.trust-alb.service_account
  }
}
