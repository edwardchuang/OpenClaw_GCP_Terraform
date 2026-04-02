#!/bin/bash
MY_IP=$(curl -s https://api.ipify.org)
echo "Current Cloud Shell IP: $MY_IP"
gcloud container clusters update openclaw-gke-prod-v2 \
    --region us-central1 \
    --enable-master-authorized-networks \
    --master-authorized-networks=$MY_IP/32
echo "GKE Master Authorized Networks updated."
