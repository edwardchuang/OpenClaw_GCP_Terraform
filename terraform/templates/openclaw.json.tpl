{
  "gateway": {
    "bind": "lan",
    "mode": "local",
    "auth": {
      "mode": "token"
    },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "env": {
    "vars": {
      "INSTANCE_NAME": "${instance_name}",
      "GOOGLE_CLOUD_PROJECT": "${project_id}",
      "GOOGLE_CLOUD_LOCATION": "${region}",
      "GOOGLE_VERTEX_BASE_URL": "https://aiplatform.googleapis.com/",
      "HTTP_PROXY": "${swp_proxy_url}",
      "HTTPS_PROXY": "${swp_proxy_url}",
      "NO_PROXY": "localhost,127.0.0.1,metadata.google.internal,169.254.169.254,10.0.0.0/8,.svc.cluster.local,.googleapis.com,googleapis.com"
    }
  },
  "plugins": {
    "entries": {
      "google": {
        "enabled": true
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "google-vertex/gemini-3.1-flash-preview"
      }
    }
  }
}
