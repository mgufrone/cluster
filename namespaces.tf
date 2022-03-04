locals {
  namespaces = ["production", "dev"]
  allNamespace = concat(local.namespaces, ["default", local.system_namespace])
}
resource "kubernetes_namespace" "all_namespaces" {
  for_each = {
  for index, namespace in local.namespaces:
  index => namespace
  }
  metadata {
    name = each.value
  }
}
