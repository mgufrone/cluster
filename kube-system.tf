locals {
  system_namespace = "kube-system"
  traefik_args = [
    "--providers.kubernetesingress=true",
    "--ping",
    "--ping.entrypoint=web",
  ]
}
resource "random_string" "webhook_token" {
  length = 12
}
data "aws_alb" "installed_alb" {
  depends_on = [helm_release.alb_ingress_controller]
  tags = {
    "elbv2.k8s.aws/cluster" = local.cluster_name
  }
}
resource "helm_release" "traefik" {
  depends_on = [local_file.kubeconfig, helm_release.cert-manager, helm_release.alb_ingress_controller]
  name       = "traefik"
  namespace  = local.system_namespace
  repository = "https://helm.traefik.io/traefik"
  chart      = "traefik"
  values = [
    file("kube-system/traefik.yaml"),
    yamlencode({
      additionalArguments = concat(local.traefik_args, ["--providers.kubernetesingress.ingressendpoint.hostname=${data.aws_alb.installed_alb.dns_name}"])
    })
  ]
}
resource "kubernetes_ingress_v1" "alb-ingress" {
  depends_on = [local_file.kubeconfig]
  metadata {
    namespace = local.system_namespace
    name      = "alb-ingress"
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate.mgufrone-xyz-certificate.arn
    }
  }
  spec {
    default_backend {
      service {
        name = "traefik"
        port {
          name = "web"
        }
      }
    }
  }
}

resource "helm_release" "cert-manager" {
  depends_on = [local_file.kubeconfig]
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  name       = "cert-manager"
  namespace  = local.system_namespace
  set {
    name  = "installCRDs"
    value = "true"
  }
  values = [
    file("./kube-system/cert-manager.yaml")
  ]
}
resource "kubernetes_manifest" "assets_compressor" {
  depends_on = [helm_release.traefik]
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "compressor"
      namespace = local.system_namespace
    }
    spec = {
      compress = {
        excludedContentTypes = ["text/event-stream"]
      }
    }
  }
}

resource "helm_release" "jenkins" {
  depends_on = [helm_release.traefik, kubernetes_secret.ghcr]
  chart      = "jenkins"
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  values = [
    file("./kube-system/jenkins.yaml")
  ]
  namespace   = local.system_namespace
  max_history = 5
  set {
    name  = "controller.tag"
    value = var.jenkins_version
  }
  set {
    name  = "controller.image"
    value = var.jenkins_image
  }
  set {
    name  = "controller.ingress.hostName"
    value = "jenkins.${local.system_namespace}.${var.domain}"
  }
  set {
    name  = "controller.ingress.annotations.traefik\\.ingress\\.kubernetes\\.io/router\\.middlewares"
    value = "${local.system_namespace}-compressor@kubernetescrd"
  }
}

resource "kubernetes_secret" "regcred" {
  depends_on = [kubernetes_namespace.all_namespaces]
  for_each = {
    for index, namespace in local.allNamespace :
    index => namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  metadata {
    namespace = each.value
    name      = "regcred"
  }
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v2" = {
          auth = base64encode("${var.DOCKER_USERNAME}:${var.DOCKER_TOKEN}")
        }
      }
    })
  }
}

resource "kubernetes_secret" "ghcr" {
  depends_on = [kubernetes_namespace.all_namespaces]
  for_each = {
    for index, namespace in local.allNamespace :
    index => namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  metadata {
    namespace = each.value
    name      = "ghcr"
  }
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://ghcr.io" = {
          auth = base64encode("${var.GITHUB_EMAIL}:${var.GITHUB_TOKEN}")
        }
      }
    })
  }
}

resource "kubernetes_default_service_account" "patch_service_account" {
  depends_on = [kubernetes_namespace.all_namespaces]
  for_each = {
    for index, namespace in local.allNamespace :
    index => namespace
  }
  image_pull_secret {
    name = "ghcr"
  }
  image_pull_secret {
    name = "regcred"
  }
  metadata {
    namespace = each.value
  }
}

resource "kubernetes_secret" "creds" {
  metadata {
    namespace = local.system_namespace
    name      = "creds"
  }
  type = "Opaque"
  data = {
    "gh-token"      = var.GITHUB_TOKEN
    "slack-app"     = var.SLACK_APP_TOKEN
    "slack-bot"     = var.SLACK_BOT_TOKEN
    "gh-username"   = var.GITHUB_EMAIL
    "webhook-token" = random_string.webhook_token.result
  }
}
