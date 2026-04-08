#!/bin/bash
CLUSTER_NAME="openclaw-gke-prod-v2"
REGION="us-central1"

echo "🔍 Getting the unhealthy node name from GKE API..."
# First ensure we have cluster credentials
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION --quiet >/dev/null 2>&1

# Get all nodes, pick the first NotReady one
NODE_NAME=$(kubectl get nodes --no-headers | grep -i "NotReady" | awk '{print $1}' | head -n 1)

if [ -z "$NODE_NAME" ]; then
    echo "✅ No Unhealthy (NotReady) nodes found for cluster $CLUSTER_NAME. Checking for Ready nodes instead..."
    NODE_NAME=$(kubectl get nodes --no-headers | awk '{print $1}' | head -n 1)
    if [ -z "$NODE_NAME" ]; then
        echo "❌ No nodes exist in the cluster yet. Wait for Autopilot to provision them."
        exit 1
    fi
fi

echo "🖥️ Target Node: $NODE_NAME"
echo "--------------------------------------------------"
echo "📜 Fetching kubelet and containerd logs via Cloud Logging..."
echo "Trying a broader search query across all GKE log types..."
echo "--------------------------------------------------"

# Try a broader query. GKE node logs can appear under different resource types 
# depending on the agent (fluentbit) configuration, such as 'k8s_node' or 'gce_instance'
# We search for any error/warning containing "network", "pull", or "cni"
gcloud logging read "resource.labels.node_name=\"$NODE_NAME\" AND severity>=WARNING" \
    --limit=20 \
    --format="table(timestamp, severity, textPayload, jsonPayload.message)"

# If nothing returned, try a raw text search for the node name in the last 1 hour
echo "--------------------------------------------------"
echo "🔎 If the table above is empty, running a fallback raw text search..."
gcloud logging read "textPayload:\"$NODE_NAME\" OR jsonPayload.message:\"$NODE_NAME\" AND severity>=WARNING" \
    --limit=20 \
    --format="table(timestamp, severity, textPayload, jsonPayload.message)"

echo "--------------------------------------------------"
echo "💡 Tip: If you see 'network plugin not initialized' or 'failed to pull image', the node is likely blocked by VPC firewalls or Cloud DNS PGA configuration."
