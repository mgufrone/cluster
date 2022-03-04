output "role_arn" {
  value = aws_iam_role.role.arn
}
output "policy_arn" {
  value = aws_iam_policy.policy.arn
}
output "service_account" {
  value = var.service_account
}
