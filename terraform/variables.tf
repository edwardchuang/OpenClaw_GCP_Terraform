variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The primary Google Cloud region for deployment"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The primary Google Cloud zone for deployment"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "The deployment environment (e.g., dev, prod)"
  type        = string
  default     = "prod"
}

variable "openclaw_instances" {
  type = map(object({
    image         = string
    gateway_token = string
  }))
  description = "Map of OpenClaw instance configurations"
}
