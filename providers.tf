terraform {
  backend "s3" {
    region = "us-east-1"
    bucket = "mgufrone.xyz"
    key    = "terraform/managed-mgufrone.xyz.state"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.72"
    }
  }
}
locals {
  tokenCommand = join(" ", [
    "aws",
    "--region",
    var.region,
    "eks",
    "get-token",
    "--cluster-name",
    local.cluster_name
  ])
}
provider "kubernetes" {
  config_path = "./kubeconfig"
}
provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    config_path = "./kubeconfig"
  }
}
