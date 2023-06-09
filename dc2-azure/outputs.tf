# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "resource_group_name" {
  description = "Azure resource group name"
  value       = azurerm_resource_group.default.name
}

output "kubernetes_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.default.name
}

output "cluster_id" {
  description = "AKS cluster ID"
  value = azurerm_kubernetes_cluster.default.id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = azurerm_kubernetes_cluster.default.portal_fqdn
}

output "region" {
  description = "AWS region"
  value       = var.region
}
