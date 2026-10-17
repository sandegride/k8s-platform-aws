data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "${var.name}-${var.environment}"
  azs          = slice(data.aws_availability_zones.available.names, 0, var.azs_count)

  tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  gpu_node_group = {
    gpu = {
      ami_type       = "AL2_x86_64_GPU"
      instance_types = var.gpu_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = 0
      max_size       = 2
      desired_size   = 0

      labels = {
        "nvidia.com/gpu.present" = "true"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = local.cluster_name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  one_nat_gateway_per_az = var.environment == "prod"
  enable_dns_hostnames   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.cluster_name
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    eks-pod-identity-agent = {}
    vpc-cni = {
      before_compute = true
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = merge(
    {
      general = {
        instance_types = var.node_instance_types
        capacity_type  = "ON_DEMAND"
        min_size       = var.node_min_size
        max_size       = var.node_max_size
        desired_size   = var.node_desired_size

        labels = {
          workload = "general"
        }
      }
    },
    var.gpu_nodes_enabled ? local.gpu_node_group : {}
  )

  access_entries = {
    for i, arn in var.admin_role_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "cert_manager_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                  = "${local.cluster_name}-cert-manager"
  attach_cert_manager_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }
}

resource "aws_s3_bucket" "loki" {
  for_each = toset(["chunks", "ruler"])

  bucket = "${local.cluster_name}-loki-${each.key}"
}

resource "aws_s3_bucket_public_access_block" "loki" {
  for_each = aws_s3_bucket.loki

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki["chunks"].id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

data "aws_iam_policy_document" "loki" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [for b in aws_s3_bucket.loki : b.arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for b in aws_s3_bucket.loki : "${b.arn}/*"]
  }
}

resource "aws_iam_policy" "loki" {
  name   = "${local.cluster_name}-loki"
  policy = data.aws_iam_policy_document.loki.json
}

module "loki_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${local.cluster_name}-loki"

  role_policy_arns = {
    loki = aws_iam_policy.loki.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:loki"]
    }
  }
}
