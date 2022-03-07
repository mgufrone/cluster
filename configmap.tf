resource "kubernetes_config_map" "job-app" {
  metadata {
    namespace = "production"
    name = "job-app"
  }
  data = yamldecode(file("./configmap/production/job-app.env"))
}


resource "kubernetes_config_map" "configmap" {
  data = yamldecode(file("./configmap/production/job-worker.env"))
  metadata {
    name = "job-worker"
    namespace = "production"
  }
}
