variable "role_name" {
  type = string
}
variable "service_account" {
  type = string
}
variable "namespace" {
  type = string
}
variable "oidc_url" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "source_json" {
  type = string
  description = "path to iam source json file"
}

variable "create_service_account" {
  type = bool
  default = true
  description = "to mark if service account should be created"
}
