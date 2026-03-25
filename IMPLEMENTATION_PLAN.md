# Implementation Plan: OpenClaw Multiple Instance Refactor

## Routing Strategy
- **Selected Strategy:** Option A (Multiple LoadBalancers for each instance).

## Resource Inventory & Separation

| Resource Category | Resource Name | Separation Status | Notes |
| :--- | :--- | :--- | :--- |
| **Shared** | `kubernetes_namespace` | Shared | Central management of instances. |
| **Shared** | `google_container_cluster` | Shared | Underlying GKE cluster. |
| **Shared** | `kubernetes_service_account` | Shared | Current setup; consider per-instance SA if strict IAM is required later. |
| **Instance-specific** | `kubernetes_deployment` | Independent | Unique instance lifecycle. |
| **Instance-specific** | `kubernetes_service` | Independent | Unique ILB and IP per instance. |
| **Instance-specific** | `kubernetes_config_map` | Independent | Unique configuration per instance. |
| **Instance-specific** | `google_compute_address` | Independent | Unique internal IP per instance. |
| **Instance-specific** | `random_password` | Independent | Unique API token per instance. |
