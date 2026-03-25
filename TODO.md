# OpenClaw Multiple Instance Refactor Plan

## 1. Requirement & Architecture Analysis
- [x] Routing strategy selected: Option A (Multiple LoadBalancers for each instance).
- [ ] Map out shared vs. instance-specific resources.

## 2. Infrastructure Refactoring
- [ ] Create `terraform/modules/openclaw-instance/` directory.
- [ ] Extract `kubernetes_deployment`, `kubernetes_service`, and `kubernetes_config_map` into the module.
- [ ] Update `terraform/variables.tf` to support a map-based definition for multiple instances.
- [ ] Refactor `terraform/08-app.tf` to use `module "openclaw_instance"` calls.

## 3. Dynamic Configuration
- [ ] Parameterize `openclaw.json.tpl` for instance-specific tags/names/settings.
- [ ] Ensure unique naming conventions (e.g., `<base_name>-<instance_name>`).
- [ ] Update `random_password` generation to be per-instance.

## 4. Verification & Deployment
- [ ] Run `terraform plan` to ensure no drift/resource destruction occurs during migration.
- [ ] Apply changes and verify independent instances are running in GKE.
- [ ] Test connectivity for multiple instances (via IAP tunnels or Ingress).

## 5. Security Enhancements (Post-Implementation)
- [ ] Upgrade token management to Google Secret Manager (GSM) with CSI Driver for production-grade security.
