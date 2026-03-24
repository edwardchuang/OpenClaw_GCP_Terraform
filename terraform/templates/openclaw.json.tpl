{
  "gateway": {
    "bind": "lan",
    "mode": "local",
    "auth": {
      "mode": "token"
    }
  },
  "env": {
    "vars": {
      "GOOGLE_CLOUD_PROJECT": "${project_id}",
      "GOOGLE_CLOUD_LOCATION": "${region}",
      "HTTP_PROXY": "${swp_proxy_url}",
      "HTTPS_PROXY": "${swp_proxy_url}",
      "NO_PROXY": "localhost,127.0.0.1,metadata.google.internal,10.0.0.0/8,.svc.cluster.local"
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "google-vertex/gemini-3.1-flash-lite-preview"
      }
    }
  }
}
