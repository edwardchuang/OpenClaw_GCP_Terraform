terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

variable "instance_name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "image" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "swp_proxy_url" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "dns_zone_name" {
  type = string
}

variable "dns_zone_dns_name" {
  type = string
}

variable "openclaw_sa_email" {
  type = string
}

variable "enable_persistence" {
  description = "If true, creates a Persistent Volume Claim to store Agent memory, logs, and config. If false, uses an ephemeral emptyDir."
  type        = bool
  default     = true
}

variable "storage_size" {
  description = "The size of the Persistent Volume for the instance (e.g., '10Gi'). Ignored if enable_persistence is false."
  type        = string
  default     = "10Gi"
}
