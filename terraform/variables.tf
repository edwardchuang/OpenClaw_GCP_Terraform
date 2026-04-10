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
    image_tag          = string
    enable_persistence = optional(bool, true)
    storage_size       = optional(string, "10Gi")
    cpu_request        = optional(string, "2000m") # Default 2 vCPU
    memory_request     = optional(string, "8Gi")   # Default 8 GB RAM
    agent_name         = optional(string, "Claw-Agent")
    agent_vibe         = optional(string, "Helpful, concise, technical")
    agent_emoji        = optional(string, "🤖")
  }))
  description = "Map of OpenClaw instance configurations"
}
