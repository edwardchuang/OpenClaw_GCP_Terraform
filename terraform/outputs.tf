output "gateway_tokens" {
  value     = { for k, v in module.openclaw_instances : k => v.gateway_token }
  sensitive = true
  description = "The dynamically generated API Tokens for all OpenClaw Gateway instances."
}
