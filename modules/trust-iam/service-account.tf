
resource "kubernetes_service_account" "service_account" {
  count = var.create_service_account ? 1 : 0
  metadata {
    name = var.service_account
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.role.arn
    }
  }
}
