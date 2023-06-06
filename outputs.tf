output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.dc1.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.dc1.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.dc1.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = module.dc1.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.dc1.cluster_name
}

output "resource_group_name" {
  description = "Azure resource group name"
  value       = module.dc2.resource_group_name
}

output "kubernetes_cluster_name" {
  description = "Azure AKS cluster name"
  value       = module.dc2.kubernetes_cluster_name
}