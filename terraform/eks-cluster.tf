module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "19.0.4"

  cluster_name = local.cluster_name
  cluster_version = "1.24"

  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    one = {
      name = "tap-ng1"

      instance_types = ["t3.xlarge"]

      min_size = 1
      max_size = 3
      desired_size = 2

      disk_size = 50
    }

    two = {
      name = "tap-ng2"

      instance_types = ["t3.xlarge"]

      min_size = 1
      max_size = 2
      desired_size = 1

      disk_size = 50
    }
  }
}