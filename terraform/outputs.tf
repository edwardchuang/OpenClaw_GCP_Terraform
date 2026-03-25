output "gateway_token" {
  value     = random_password.gateway_token.result
  sensitive = true
  description = "The dynamically generated API Token for the OpenClaw Gateway."
}
