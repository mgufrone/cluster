data "aws_route53_zone" "main_host" {
  name = var.domain
}
resource "aws_acm_certificate" "mgufrone-xyz-certificate" {
  domain_name       = "*.${data.aws_route53_zone.main_host.name}"
  subject_alternative_names = concat([
    "*.dev.${data.aws_route53_zone.main_host.name}",
    ], var.alt_domains)
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}
data "aws_eks_cluster_auth" "this" {
#  depends_on = [module.eks]
  name = module.eks.cluster_id
}
locals {
  cluster_name   = "cluster-${replace(var.domain, ".", "-")}-v4"
  bootstrap_data = <<-EOT
export CONTAINER_RUNTIME="containerd"
EOT

  kubeconfig = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = local.cluster_name
    clusters = [{
      name = module.eks.cluster_id
      cluster = {
        certificate-authority-data = module.eks.cluster_certificate_authority_data
        server                     = module.eks.cluster_endpoint
      }
    }]
    contexts = [{
      name = local.cluster_name
      context = {
        cluster = module.eks.cluster_id
        user    = "terraform"
      }
    }]
    users = [{
      name = "terraform"
      user = {
        exec = {
          apiVersion = "client.authentication.k8s.io/v1alpha1"
          args = [
            "--region",
            var.region,
            "eks",
            "get-token",
            "--cluster-name",
            local.cluster_name
          ]
          command = "aws"
          interactiveMode = "IfAvailable"
          provideClusterInfo = false
        }
      }
    }]
  })
}

data "aws_availability_zones" "available" {
  exclude_names = ["us-east-1b", "us-east-1f", "us-east-1e"]
}
data "aws_ami" "eks_default" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }
}

data "aws_eks_cluster" "this" {
  depends_on = [module.eks]
  name = local.cluster_name
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.cluster_name
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
  public_subnets  = ["10.0.64.0/20", "10.0.80.0/20", "10.0.96.0/20"]

  enable_ipv6                     = true
  assign_ipv6_address_on_creation = false
  create_egress_only_igw          = true

  public_subnet_ipv6_prefixes  = [0, 1, 2]
  private_subnet_ipv6_prefixes = [3, 4, 5]

  enable_nat_gateway   = false
  single_nat_gateway   = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

}
module "eks" {
  source      = "terraform-aws-modules/eks/aws"
  version     = "~> 18.7.2"

  cluster_name                    = local.cluster_name
  cluster_version                 = var.cluster_version
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  subnet_ids                      = module.vpc.public_subnets
  vpc_id                          = module.vpc.vpc_id
  cluster_service_ipv4_cidr       = "10.1.0.0/16"
  self_managed_node_group_defaults = {
    subnet_ids        = module.vpc.public_subnets
    disk_size         = 30
    ami_type          = "AL2_x86_64"
    enable_monitoring = false
    ami_release_version = var.worker_version
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 2
      instance_metadata_tags      = "disabled"
    }
    use_name_prefix = true
    use_mixed_instances_policy = true
    bootstrap_extra_args = "--container-runtime containerd --dns-cluster-ip 10.1.0.10"
    #    ami_id                     = data.aws_ami.eks_default.image_id
    pre_bootstrap_user_data = <<-EOT
      export CONTAINER_RUNTIME="containerd"
    EOT
  }
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    service_cidr = {
      description = "additional service subnets"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks      = ["10.1.112.0/24"]
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    alb_resolver = {
      description = "alb port requirement"
      protocol    = "TCP"
      from_port   = 9443
      to_port     = 9443
      type        = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }
  cluster_addons = {
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {}
    vpc-cni = {
      resolve_conflicts        = "OVERWRITE"
    }
  }
  self_managed_node_groups = {
    general = {
      max_size            = 5
      min_size            = 1
      desired_size        = 1

      bootstrap_extra_args = "--container-runtime containerd --dns-cluster-ip 10.1.0.10 --kubelet-extra-args \"--node-labels=purpose=general\""
      mixed_instances_policy = {
        instances_distribution = {
          on_demand_base_capacity                  = 0
          on_demand_percentage_above_base_capacity = 0
          spot_allocation_strategy                 = "capacity-optimized"
        }

        override = [
          {
            instance_type     = "m5a.large"
            weighted_capacity = "1"
          },
          {
            instance_type     = "m6i.large"
            weighted_capacity = "2"
          },
        ]
      }
      bootstrap_env = {
        CONTAINER_RUNTIME = "containerd"
      }
      capacity_type = "SPOT"

      k8s_labels = {
        purpose = "general"
      }
      tags = {
        "k8s.io/cluster-autoscaler/${local.cluster_name}" : "owned"
        "k8s.io/cluster-autoscaler/enabled" : "true"
        "k8s.io/cluster-autoscaler/node-template/label/purpose" : "general"
      }
      public_ip             = true
    }
    builder = {
      use_name_prefix     = true
      public_ip           = false
      desired_size        = 0
      max_size            = 4
      min_size            = 0
      disk_size           = 30
      ami_release_version = var.worker_version

      bootstrap_extra_args = "--container-runtime containerd --dns-cluster-ip 10.1.0.10 --kubelet-extra-args \"--node-labels=purpose=builder,builder=medium --register-with-taints=builder=true:NoSchedule\""
      mixed_instances_policy = {
        instances_distribution = {
          on_demand_base_capacity                  = 0
          on_demand_percentage_above_base_capacity = 0
          spot_allocation_strategy                 = "capacity-optimized"
        }

        override = [
          {
            instance_type     = "t3a.xlarge"
            weighted_capacity = "1"
          },
        ]
      }
      instance_types = ["t3a.xlarge"]
      capacity_type  = "SPOT"
      k8s_labels = {
        purpose = "builder"
        builder = "medium"
      }
      taints = [
        {
          key    = "builder"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
      bootstrap_env = {
        CONTAINER_RUNTIME = "containerd"
      }
      tags = {
        "k8s.io/cluster-autoscaler/${local.cluster_name}" : "owned"
        "k8s.io/cluster-autoscaler/enabled" : "true"
        "k8s.io/cluster-autoscaler/node-template/label/purpose" : "builder"
        "k8s.io/cluster-autoscaler/node-template/label/builder" : "medium"
        "k8s.io/cluster-autoscaler/node-template/taint/builder" : "true:NoSchedule"
      }
    }
  }
}
resource "local_file" "kubeconfig" {
  filename = "kubeconfig"
  content = local.kubeconfig
  file_permission = "0600"
}
resource "null_resource" "apply" {
  triggers = {
    kubeconfig = base64encode(local.kubeconfig)
    cmd_patch  = <<-EOT
      kubectl create configmap aws-auth -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)
      kubectl patch configmap/aws-auth --patch "${module.eks.aws_auth_configmap_yaml}" -n kube-system --kubeconfig <(echo $KUBECONFIG | base64 --decode)
    EOT
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
    command = self.triggers.cmd_patch
  }
}
