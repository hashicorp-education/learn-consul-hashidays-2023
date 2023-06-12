# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ca-central-1"
}

variable "network_region" {
  description = "Azure region"
  type        = string
  default     = "West US 2"
}