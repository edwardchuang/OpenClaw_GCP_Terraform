# ---------------------------------------------------------
# Stage 1: Builder
# Install npm packages in a full Node environment
# ---------------------------------------------------------
FROM node:20-slim AS builder

WORKDIR /app

# Initialize a package.json
RUN npm init -y

# Install desired skills from ClawHub / npm ecosystem
# We install @modelcontextprotocol/sdk to ensure compatibility
RUN npm install @modelcontextprotocol/sdk

# ---------------------------------------------------------
# Stage 2: Final Minimal Image
# Note on "Distroless": The official ghcr.io/openclaw/openclaw image
# is already built on a slim alpine/node base and requires specific 
# entrypoint scripts to function as the gateway/agent.
# Replacing the base OS entirely with distroless/nodejs often breaks 
# the internal IPC/socket mechanisms of OpenClaw.
# Therefore, the most secure and reliable approach is to use the official 
# image as the base and only copy in the pre-compiled node_modules 
# without leaving npm, git, or build tools in the final layer.
# ---------------------------------------------------------
FROM ghcr.io/openclaw/openclaw:latest

# We run as the non-root user defined in the official image
USER root

# Create directory for custom skills
RUN mkdir -p /home/node/custom-skills && chown -R node:node /home/node/custom-skills

# Copy installed skills from the builder stage
COPY --from=builder --chown=node:node /app/node_modules /home/node/custom-skills/node_modules
COPY --from=builder --chown=node:node /app/package.json /home/node/custom-skills/package.json

# Switch back to the secure non-root user
USER node

# Set NODE_PATH so Node.js knows where to find these global-like modules
ENV NODE_PATH=/home/node/custom-skills/node_modules:$NODE_PATH

# The entrypoint remains the default from ghcr.io/openclaw/openclaw
