# Main Terraform configuration for AWS EKS infrastructure

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
  
  backend "s3" {
    bucket         = "laravel-terraform-state"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = var.common_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# Local variables
locals {
  env_name = var.environment
  app_name = "laravel"
  
  cluster_name = "${local.app_name}-eks-${local.env_name}"
  
  common_tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Application = local.app_name
    }
  )
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  name               = "${local.app_name}-vpc-${local.env_name}"
  cidr              = var.vpc_cidr
  availability_zones = data.aws_availability_zones.available.names
  
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  
  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod"
  
  tags = local.common_tags
}

# EKS Module
module "eks" {
  source = "./modules/eks"
  
  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  node_groups = var.node_groups
  
  tags = local.common_tags
}

# RDS Module
module "rds" {
  source = "./modules/rds"
  
  identifier     = "${local.app_name}-db-${local.env_name}"
  engine         = "postgres"
  engine_version = "15.3"
  
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  
  db_name  = "laravel"
  username = "laravel_user"
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  security_groups = [module.eks.cluster_security_group_id]
  
  backup_retention_period = var.environment == "prod" ? 30 : 7
  skip_final_snapshot    = var.environment != "prod"
  
  tags = local.common_tags
}

# ElastiCache Redis Module
module "elasticache" {
  source = "./modules/elasticache"
  
  name           = "${local.app_name}-redis-${local.env_name}"
  node_type      = var.redis_node_type
  num_cache_nodes = var.environment == "prod" ? 2 : 1
  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  security_groups = [module.eks.cluster_security_group_id]
  
  tags = local.common_tags
}

# ECR Module
module "ecr" {
  source = "./modules/ecr"
  
  repository_name = "${local.app_name}"
  
  image_retention_count = var.environment == "prod" ? 30 : 10
  
  tags = local.common_tags
}

# IAM Module
module "iam" {
  source = "./modules/iam"
  
  environment = var.environment
  cluster_name = module.eks.cluster_name
  
  ecr_repository_arn = module.ecr.repository_arn
  s3_bucket_arns    = [module.s3.bucket_arn]
  
  tags = local.common_tags
}

# S3 Module for application storage
module "s3" {
  source = "./modules/s3"
  
  bucket_name = "${local.app_name}-storage-${local.env_name}-${data.aws_caller_identity.current.account_id}"
  
  versioning_enabled = var.environment == "prod"
  
  lifecycle_rules = [
    {
      id      = "cleanup"
      enabled = true
      
      transition = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      
      expiration = {
        days = var.environment == "prod" ? 365 : 90
      }
    }
  ]
  
  tags = local.common_tags
}

# Outputs
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.ecr.repository_url
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.elasticache.primary_endpoint_address
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket name for application storage"
  value       = module.s3.bucket_name
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}