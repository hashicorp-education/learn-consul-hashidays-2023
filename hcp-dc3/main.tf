locals {
  hvn_region     = "eastus"
  hvn_id         = "learn-consul-hashidays-demo-az-hvn"
  cluster_id     = "learn-consul-hashidays-demo-az"
  network_region = "eastus"
  vnet_cidrs     = ["10.0.0.0/16"]
  vnet_subnets = {
    "subnet1" = "10.0.1.0/24",
    "subnet2" = "10.0.2.0/24",
  }
}

terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 2.65"
      configuration_aliases = [azurerm.azure]
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.14"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.23.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.4.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.11.3"
    }
  }

  required_version = ">= 1.0.11"

}

# Configure providers to use the credentials from the AKS cluster.
provider "helm" {
  kubernetes {
    client_certificate     = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.cluster_ca_certificate)
    host                   = azurerm_kubernetes_cluster.k8.kube_config.0.host
    password               = azurerm_kubernetes_cluster.k8.kube_config.0.password
    username               = azurerm_kubernetes_cluster.k8.kube_config.0.username
  }
}

provider "kubernetes" {
  client_certificate     = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.cluster_ca_certificate)
  host                   = azurerm_kubernetes_cluster.k8.kube_config.0.host
  password               = azurerm_kubernetes_cluster.k8.kube_config.0.password
  username               = azurerm_kubernetes_cluster.k8.kube_config.0.username
}

provider "kubectl" {
  client_certificate     = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.k8.kube_config.0.cluster_ca_certificate)
  host                   = azurerm_kubernetes_cluster.k8.kube_config.0.host
  load_config_file       = false
  password               = azurerm_kubernetes_cluster.k8.kube_config.0.password
  username               = azurerm_kubernetes_cluster.k8.kube_config.0.username
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

provider "hcp" {}

provider "consul" {
  address    = hcp_consul_cluster.main.consul_public_endpoint_url
  datacenter = hcp_consul_cluster.main.datacenter
  token      = hcp_consul_cluster_root_token.token.secret_id
}
data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "${local.cluster_id}-gid"
  location = local.network_region
}

resource "azurerm_route_table" "rt" {
  name                = "${local.cluster_id}-rt"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${local.cluster_id}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create an Azure vnet and authorize Consul server traffic.
module "network" {
  source              = "Azure/vnet/azurerm"
  version             = "~> 2.6.0"
  address_space       = local.vnet_cidrs
  resource_group_name = azurerm_resource_group.rg.name
  subnet_names        = keys(local.vnet_subnets)
  subnet_prefixes     = values(local.vnet_subnets)
  vnet_name           = "${local.cluster_id}-vnet"

  # Every subnet will share a single route table
  route_tables_ids = { for i, subnet in keys(local.vnet_subnets) : subnet => azurerm_route_table.rt.id }

  # Every subnet will share a single network security group
  nsg_ids = { for i, subnet in keys(local.vnet_subnets) : subnet => azurerm_network_security_group.nsg.id }

  depends_on = [azurerm_resource_group.rg]
}

# Create an HCP HVN.
resource "hcp_hvn" "hvn" {
  cidr_block     = "172.25.32.0/20"
  cloud_provider = "azure"
  hvn_id         = local.hvn_id
  region         = local.hvn_region
}

# Note: Uncomment the below module to setup peering for connecting to a private HCP Consul cluster
# Peer the HVN to the vnet.
# module "hcp_peering" {
#   source  = "hashicorp/hcp-consul/azurerm"
#   version = "~> 0.3.1"

#   hvn    = hcp_hvn.hvn
#   prefix = local.cluster_id

#   security_group_names = [azurerm_network_security_group.nsg.name]
#   subscription_id      = data.azurerm_subscription.current.subscription_id
#   tenant_id            = data.azurerm_subscription.current.tenant_id

#   subnet_ids = module.network.vnet_subnets
#   vnet_id    = module.network.vnet_id
#   vnet_rg    = azurerm_resource_group.rg.name
# }

# Create the Consul cluster.
resource "hcp_consul_cluster" "main" {
  cluster_id         = local.cluster_id
  hvn_id             = hcp_hvn.hvn.hvn_id
  public_endpoint    = true
  tier               = "development"
  min_consul_version = "v1.14.0"
}

resource "hcp_consul_cluster_root_token" "token" {
  cluster_id = hcp_consul_cluster.main.id
}

# Create a user assigned identity (required for UserAssigned identity in combination with brining our own subnet/nsg/etc)
resource "azurerm_user_assigned_identity" "identity" {
  name                = "aks-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create the AKS cluster.
resource "azurerm_kubernetes_cluster" "k8" {
  name                    = local.cluster_id
  dns_prefix              = local.cluster_id
  location                = azurerm_resource_group.rg.location
  private_cluster_enabled = false
  resource_group_name     = azurerm_resource_group.rg.name

  network_profile {
    network_plugin     = "azure"
    service_cidr       = "10.30.0.0/16"
    dns_service_ip     = "10.30.0.10"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  default_node_pool {
    name            = "default"
    node_count      = 3
    vm_size         = "Standard_D2_v2"
    os_disk_size_gb = 30
    pod_subnet_id   = module.network.vnet_subnets[0]
    vnet_subnet_id  = module.network.vnet_subnets[1]
  }

  identity {
    type                      = "UserAssigned"
    user_assigned_identity_id = azurerm_user_assigned_identity.identity.id
  }

  depends_on = [module.network]
}

# Create a Kubernetes client that deploys Consul and its secrets.
module "aks_consul_client" {
  source  = "hashicorp/hcp-consul/azurerm//modules/hcp-aks-client"
  version = "~> 0.3.1"

  cluster_id = hcp_consul_cluster.main.cluster_id
  # strip out url scheme from the public url
  consul_hosts       = tolist([substr(hcp_consul_cluster.main.consul_public_endpoint_url, 8, -1)])
  consul_version     = hcp_consul_cluster.main.consul_version
  k8s_api_endpoint   = azurerm_kubernetes_cluster.k8.kube_config.0.host
  boostrap_acl_token = hcp_consul_cluster_root_token.token.secret_id
  datacenter         = hcp_consul_cluster.main.datacenter

  # The AKS node group will fail to create if the clients are
  # created at the same time. This forces the client to wait until
  # the node group is successfully created.
  depends_on = [azurerm_kubernetes_cluster.k8]
}

# Deploy Hashicups.
module "demo_app" {
  source  = "hashicorp/hcp-consul/azurerm//modules/k8s-demo-app"
  version = "~> 0.3.1"

  depends_on = [module.aks_consul_client]
}

# Authorize HTTP ingress to the load balancer.
resource "azurerm_network_security_rule" "ingress" {
  name                        = "http-ingress"
  priority                    = 301
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "*"
  destination_address_prefix  = module.demo_app.load_balancer_ip
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name

  depends_on = [module.demo_app]
}

output "consul_root_token" {
  value     = hcp_consul_cluster_root_token.token.secret_id
  sensitive = true
}

output "consul_url" {
  value = hcp_consul_cluster.main.consul_public_endpoint_url
}

output "hashicups_url" {
  value = "${module.demo_app.hashicups_url}:8080"
}

output "next_steps" {
  value = "Hashicups Application will be ready in ~2 minutes. Use 'terraform output consul_root_token' to retrieve the root token."
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.k8.kube_config_raw
  sensitive = true
}


# locals {
#   vpc_region          = "us-east-1"
#   hvn_region          = "us-east-1"
#   cluster_id          = "learn-consul-hashidays-demo-a"
#   hvn_id              = "learn-consul-hashidays-demo-a-hvn"
#   install_demo_app    = true
#   install_eks_cluster = true
# }

# terraform {
#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 3.43"
#     }

#     hcp = {
#       source  = "hashicorp/hcp"
#       version = ">= 0.18.0"
#     }

#     kubernetes = {
#       source  = "hashicorp/kubernetes"
#       version = "~> 2.14.0"
#     }

#     helm = {
#       source  = "hashicorp/helm"
#       version = "~> 2.7.0"
#     }

#     kubectl = {
#       source  = "gavinbunney/kubectl"
#       version = "~> 1.14.0"
#     }
#   }

# }

# provider "aws" {
#   region = local.vpc_region
# }

# provider "helm" {
#   kubernetes {
#     host                   = local.install_eks_cluster ? data.aws_eks_cluster.cluster[0].endpoint : ""
#     cluster_ca_certificate = local.install_eks_cluster ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority.0.data) : ""
#     token                  = local.install_eks_cluster ? data.aws_eks_cluster_auth.cluster[0].token : ""
#   }
# }

# provider "kubernetes" {
#   host                   = local.install_eks_cluster ? data.aws_eks_cluster.cluster[0].endpoint : ""
#   cluster_ca_certificate = local.install_eks_cluster ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority.0.data) : ""
#   token                  = local.install_eks_cluster ? data.aws_eks_cluster_auth.cluster[0].token : ""
# }

# provider "kubectl" {
#   host                   = local.install_eks_cluster ? data.aws_eks_cluster.cluster[0].endpoint : ""
#   cluster_ca_certificate = local.install_eks_cluster ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority.0.data) : ""
#   token                  = local.install_eks_cluster ? data.aws_eks_cluster_auth.cluster[0].token : ""
#   load_config_file       = false
# }
# data "aws_availability_zones" "available" {
#   filter {
#     name   = "zone-type"
#     values = ["availability-zone"]
#   }
# }

# module "vpc" {
#   source  = "terraform-aws-modules/vpc/aws"
#   version = "2.78.0"

#   name                 = "${local.cluster_id}-vpc"
#   cidr                 = "10.0.0.0/16"
#   azs                  = data.aws_availability_zones.available.names
#   public_subnets       = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
#   private_subnets      = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
#   enable_nat_gateway   = true
#   single_nat_gateway   = true
#   enable_dns_hostnames = true
# }

# data "aws_eks_cluster" "cluster" {
#   count = local.install_eks_cluster ? 1 : 0
#   name  = module.eks[0].cluster_id
# }

# data "aws_eks_cluster_auth" "cluster" {
#   count = local.install_eks_cluster ? 1 : 0
#   name  = module.eks[0].cluster_id
# }

# module "eks" {
#   count                  = local.install_eks_cluster ? 1 : 0
#   source                 = "terraform-aws-modules/eks/aws"
#   version                = "17.24.0"
#   kubeconfig_api_version = "client.authentication.k8s.io/v1beta1"

#   cluster_name    = "${local.cluster_id}-eks"
#   cluster_version = "1.25"
#   subnets         = module.vpc.private_subnets
#   vpc_id          = module.vpc.vpc_id

#   manage_aws_auth = false

#   node_groups = {
#     application = {
#       name_prefix    = "hashicups"
#       instance_types = ["t3a.medium"]

#       desired_capacity = 3
#       max_capacity     = 3
#       min_capacity     = 3
#     }
#   }
# }

# # The HVN created in HCP
# resource "hcp_hvn" "main" {
#   hvn_id         = local.hvn_id
#   cloud_provider = "aws"
#   region         = local.hvn_region
#   cidr_block     = "172.25.32.0/20"
# }

# resource "hcp_consul_cluster" "main" {
#   cluster_id         = local.cluster_id
#   hvn_id             = hcp_hvn.main.hvn_id
#   public_endpoint    = true
#   tier               = "development"
#   min_consul_version = "v1.14.0"
# }

# resource "hcp_consul_cluster_root_token" "token" {
#   cluster_id = hcp_consul_cluster.main.id
# }

# module "eks_consul_client" {
#   source  = "hashicorp/hcp-consul/aws//modules/hcp-eks-client"
#   version = "~> 0.12.1"

#   boostrap_acl_token = hcp_consul_cluster_root_token.token.secret_id
#   cluster_id         = hcp_consul_cluster.main.cluster_id
#   # strip out url scheme from the public url
#   consul_hosts     = tolist([substr(hcp_consul_cluster.main.consul_public_endpoint_url, 8, -1)])
#   consul_version   = hcp_consul_cluster.main.consul_version
#   datacenter       = hcp_consul_cluster.main.datacenter
#   k8s_api_endpoint = local.install_eks_cluster ? module.eks[0].cluster_endpoint : ""

#   # The EKS node group will fail to create if the clients are
#   # created at the same time. This forces the client to wait until
#   # the node group is successfully created.
#   depends_on = [module.eks]
# }

# module "demo_app" {
#   count   = local.install_demo_app ? 1 : 0
#   source  = "hashicorp/hcp-consul/aws//modules/k8s-demo-app"
#   version = "~> 0.12.1"

#   depends_on = [module.eks_consul_client]
# }

# output "consul_root_token" {
#   value     = hcp_consul_cluster_root_token.token.secret_id
#   sensitive = true
# }

# output "consul_url" {
#   value = hcp_consul_cluster.main.public_endpoint ? (
#     hcp_consul_cluster.main.consul_public_endpoint_url
#     ) : (
#     hcp_consul_cluster.main.consul_private_endpoint_url
#   )
# }

# output "kubeconfig_filename" {
#   value = abspath(one(module.eks[*].kubeconfig_filename))
# }

# output "helm_values_filename" {
#   value = abspath(module.eks_consul_client.helm_values_file)
# }

# output "hashicups_url" {
#   value = "${one(module.demo_app[*].hashicups_url)}:8080"
# }

# output "next_steps" {
#   value = "HashiCups Application will be ready in ~2 minutes. Use 'terraform output -raw consul_root_token' to retrieve the root token."
# }

# output "howto_connect" {
#   value = <<EOF
#   ${local.install_demo_app ? "The demo app, HashiCups, Has been installed for you and its components registered in Consul." : ""}
#   ${local.install_demo_app ? "To access HashiCups navigate to: ${one(module.demo_app[*].hashicups_url)}:8080" : ""}

#   To access Consul from your local client run:
#   export CONSUL_HTTP_ADDR="${hcp_consul_cluster.main.consul_public_endpoint_url}"
#   export CONSUL_HTTP_TOKEN=$(terraform output -raw consul_root_token)
  
#   ${local.install_eks_cluster ? "You can access your provisioned eks cluster by first running following command" : ""}
#   ${local.install_eks_cluster ? "export KUBECONFIG=$(terraform output -raw kubeconfig_filename)" : ""}    

#   Consul has been installed in the default namespace. To explore what has been installed run:
  
#   kubectl get pods

#   EOF
# }
