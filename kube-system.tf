locals {
  system_namespace = "kube-system"
  traefik_args = [
    "--providers.kubernetesingress=true",
    "--ping",
    "--ping.entrypoint=web",
  ]
  dashboards = ["app-log", "kubernetes-monitor", "stats"]
}
resource "random_string" "webhook_token" {
  length = 12
}
resource "random_string" "mysql_user_password" {
  length      = 16
  min_lower   = 2
  min_numeric = 2
  min_upper   = 2
}
resource "random_string" "grafana_password" {
  length      = 16
  min_lower   = 2
  min_numeric = 2
  min_upper   = 2
}
resource "random_string" "mysql_password" {
  length      = 16
  min_lower   = 2
  min_numeric = 2
  min_upper   = 2
}
resource "random_string" "redis_password" {
  length      = 16
  min_lower   = 2
  min_numeric = 2
  min_upper   = 2
}
resource "random_string" "rabbitmq_password" {
  length      = 16
  min_lower   = 2
  min_numeric = 2
  min_upper   = 2
}
resource "random_string" "rabbitmq_cookie" {
  length      = 16
  min_lower   = 2
  min_numeric = 2
  min_upper   = 2
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
resource "kubernetes_manifest" "traefik_dashboard" {
  depends_on = [helm_release.traefik]
  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "dashboard"
      namespace = local.system_namespace
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match = "Host(`traefik.localhost`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
          kind = "Rule"
          services = [
            {
              name = "api@internal"
              kind = "TraefikService"
            }
          ]
        }
      ]
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
module "trust-s3" {
  depends_on = [local_file.kubeconfig, kubernetes_namespace.all_namespaces]
  for_each = {
  for index, namespace in local.allNamespace:
  index => namespace
  }
  source          = "./modules/trust-iam"
  service_account = "default"
  namespace       = each.value
  cluster_name    = local.cluster_name
  oidc_url        = module.eks.cluster_oidc_issuer_url
  source_json     = file("./iam/s3-artifacts.json")
  role_name       = "s3-role-${each.value}-default"
  create_service_account = false
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
    annotations = {
      "eks.amazonaws.com/role-arn" = replace(module.trust-s3[0].role_arn, "${kubernetes_namespace.all_namespaces[0].metadata[0].name}:default", "${each.value}:default")
    }
    namespace = each.value
  }
}

resource "kubernetes_secret" "creds" {
  depends_on = [kubernetes_namespace.all_namespaces]
  for_each = {
    for index, namespace in local.allNamespace :
    index => namespace
  }
  metadata {
    namespace = each.value
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
resource "kubernetes_secret" "db-creds" {
  depends_on = [kubernetes_namespace.all_namespaces]
  for_each = {
    for index, namespace in local.allNamespace :
    index => namespace
  }
  metadata {
    namespace = each.value
    name      = "db-creds"
  }
  type = "Opaque"
  data = {
    "redis"      = random_string.redis_password.result
    "mysql-root" = random_string.mysql_password.result
    "mysql-user" = random_string.mysql_user_password.result
  }
}

resource "helm_release" "prometheus" {
  chart      = "prometheus"
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/prometheus.yaml"),
  ]
}
resource "helm_release" "prometheus-adapter" {
  chart      = "prometheus-adapter"
  name       = "prometheus-adapter"
  repository = "https://prometheus-community.github.io/helm-charts"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/prometheus-adapter.yaml"),
  ]
}

resource "helm_release" "promtail" {
  chart      = "promtail"
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/promtail.yaml"),
  ]
  set {
    name  = "loki.serviceName"
    value = "loki"
  }
}
resource "helm_release" "loki" {
  chart      = "loki"
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/loki.yaml"),
  ]
}
# grafana
resource "helm_release" "grafana" {
  chart      = "grafana"
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/grafana.yaml"),
    yamlencode({
      ingress = {
        hosts = ["monitoring.${local.system_namespace}.${var.domain}"]
      }
      envValueFrom = {
        MYSQL_ROOT_PASSWORD = {
          secretKeyRef = {
            name = "db-creds"
            key  = "mysql-root"
          }
        }
        SLACK_TOKEN = {
          secretKeyRef = {
            name = "creds"
            key  = "slack-bot"
          }
        }
      }
    })
  ]
  set {
    name  = "adminUsername"
    value = "admin"
  }
  set {
    name  = "adminPassword"
    value = random_string.grafana_password.result
  }
}

## grafana dashboard
resource "kubernetes_config_map" "dashboard" {
  metadata {
    namespace = local.system_namespace
    name      = "grafana-dashboards"
  }
  data = {
    "app-log.json"            = file("./kube-system/dashboard/app-log.json")
    "kubernetes-monitor.json" = file("./kube-system/dashboard/kubernetes-monitor.json")
    "stats.json"              = file("./kube-system/dashboard/stats.json")
  }
}

## rabbitmq
resource "kubernetes_secret" "queue-manager" {
  for_each = {
    for index, namespace in local.allNamespace :
    index => namespace
  }
  metadata {
    name      = "queue-manager"
    namespace = each.value
  }
  type = "Opaque"
  data = {
    "rabbitmq-username"      = "rabbit-monitoring"
    "rabbitmq-password"      = random_string.rabbitmq_password.result
    "rabbitmq-erlang-cookie" = random_string.rabbitmq_cookie.result
    "rabbitmq-host"          = "rabbitmq.${local.system_namespace}"
  }
}
resource "helm_release" "rabbitmq" {
  chart      = "rabbitmq"
  name       = "rabbitmq"
  repository = "https://charts.bitnami.com/bitnami"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/rabbitmq.yaml"),
  ]
  set {
    name  = "ingress.hostname"
    value = "queues.${local.system_namespace}.${var.domain}"
  }
}

resource "helm_release" "redis" {
  chart      = "redis"
  name       = "redis"
  repository = "https://charts.bitnami.com/bitnami"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/redis.yaml"),
  ]
  set {
    name  = "auth.password"
    value = random_string.redis_password.result
  }
}

## external dns
module "trust-external-dns" {
  depends_on      = [local_file.kubeconfig]
  source          = "./modules/trust-iam"
  service_account = "external-dns"
  namespace       = local.system_namespace
  cluster_name    = local.cluster_name
  oidc_url        = module.eks.cluster_oidc_issuer_url
  source_json     = file("./iam/external-dns.json")
  role_name       = "external-dns"
}
resource "helm_release" "external_dns" {
  chart      = "external-dns"
  name       = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/external-dns.yaml"),
    yamlencode({
      domainFilters = [var.domain, "mgufrone.xyz", "mgufron.com"]
      provider      = "aws"
      serviceAccount = {
        create = false
        name   = module.trust-external-dns.service_account
      }
      txtPrefix = local.cluster_name
    })
  ]
}
resource "helm_release" "mysql" {
  chart      = "mysql"
  name       = "mysql"
  repository = "https://charts.bitnami.com/bitnami"
  namespace  = local.system_namespace
  values = [
    file("./kube-system/mysql.yaml"),
    yamlencode({
      auth = {
        database     = "jobs"
        username     = "normal_user"
        password     = random_string.mysql_user_password.result
        rootPassword = random_string.mysql_password.result
      }
    })
  ]
}

resource "kubernetes_cluster_role_binding" "jenkins-admin" {
  metadata {
    name = "jenkins-admin-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind = "ServiceAccount"
    name = "jenkins"
    namespace = local.system_namespace
  }
  subject {
    kind = "ServiceAccount"
    name = "default"
    namespace = local.system_namespace
  }
}

resource "helm_release" "keda" {
  depends_on = [local_file.kubeconfig]
  chart = "keda"
  repository = "https://kedacore.github.io/charts"
  name  = "keda"
  namespace = local.system_namespace
  values = [
    file("./kube-system/keda.yaml"),
  ]
}
resource "kubernetes_secret" "keda-rabbitmq-auth" {
  depends_on = [helm_release.keda]
  for_each = {
    for i, v in local.allNamespace:
    i => v
  }
  metadata {
    name = "keda-rabbitmq-auth"
    namespace = each.value
  }
  data = {
    host = "amqp://rabbit-monitoring:'${random_string.rabbitmq_password.result}'@rabbitmq-headless.kube-system:5672/"
  }
}

resource "kubernetes_manifest" "keda-rabbit-auth" {
  depends_on = [helm_release.keda]
  for_each = {
  for i, v in local.allNamespace:
  i => v
  }
  manifest = yamldecode(templatefile("./templates/keda-rabbit-auth.tftpl", {
    namespace = each.value
    name = "keda-rabbitmq-auth"
    targetRefName = "keda-rabbitmq-auth"
  }))
}

