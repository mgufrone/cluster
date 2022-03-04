variable "region" {
  type        = string
  default     = "us-east-1"
  description = "aws region"
}

variable "cluster_version" {
  type        = string
  description = "kubernetes cluster and node version"
  default     = "1.21"
}

variable "domain" {
  type        = string
  description = "default domain as namespace"
}
variable "alt_domains" {
  type = list(string)
  default = [
    "*.kube-system.mgufrone.dev",
    "*.mgufrone.xyz",
    "*.dev.mgufrone.xyz",
    "*.mgufron.com",
    "*.dev.mgufron.com",
  ]
  description = "additional domain to be registered as alternate ssl domains"
}
variable "worker_version" {
  type        = string
  default     = "1.21.5-20211109"
  description = "default domain as namespace"
}

variable "jenkins_version" {
  type = string
  default = "1.12.0"
  description = "jenkins version"
}
variable "jenkins_image" {
  type = string
  default = "mgufrone/jenkins-plugin"
  description = "jenkins image repo"
}

variable "GITHUB_TOKEN" {
  type = string
  sensitive = true
}
variable "SLACK_APP_TOKEN" {
  type = string
  sensitive = true
}
variable "SLACK_BOT_TOKEN" {
  type = string
  sensitive = true
}
variable "DOCKER_USERNAME" {
}
variable "DOCKER_TOKEN" {
  sensitive = true
}
variable "GITHUB_EMAIL" {

}
