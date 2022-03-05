output "mysql_password" {
  value = random_string.mysql_password.result
  sensitive = true
}
output "redis_password" {
  value = random_string.redis_password.result
  sensitive = true
}
output "rabbitmq_password" {
  value = random_string.rabbitmq_password.result
  sensitive = true
}
output "rabbitmq_cookie" {
  value = random_string.rabbitmq_cookie.result
  sensitive = true
}
output "grafana_password" {
  value = random_string.grafana_password.result
  sensitive = true
}
output "kubeconfig" {
  value = local.kubeconfig

}
output "github_webhook" {
  value = random_string.webhook_token.result
  sensitive = true
}
