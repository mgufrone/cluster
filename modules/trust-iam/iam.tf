
locals {
  oidc = replace(var.oidc_url, "https://", "")
}
data "aws_caller_identity" "identity" {}
data "aws_iam_policy_document" "cni_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.identity.account_id}:oidc-provider/${local.oidc}"]
    }
    condition {
      test     = "StringEquals"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
      variable = "${local.oidc}:sub"
    }
  }
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.identity.account_id}:oidc-provider/${local.oidc}"]
    }
    condition {
      test     = "StringEquals"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
      variable = "${local.oidc}:sub"
    }
  }
}
resource "aws_iam_role" "role" {
  assume_role_policy = data.aws_iam_policy_document.cni_assume_role.json
  name               = join("-", [var.cluster_name, var.role_name])
}
resource "aws_iam_role_policy_attachment" "policy_attachment" {
  policy_arn = aws_iam_policy.policy.arn
  role       = aws_iam_role.role.name
}
data "aws_iam_policy_document" "policy_document" {
  source_policy_documents = [var.source_json]
}
resource "aws_iam_policy" "policy" {
  name_prefix = "eks-worker-${var.cluster_name}"
  description = "EKS iam policy for ${var.role_name}"
  policy      = data.aws_iam_policy_document.policy_document.json
}
