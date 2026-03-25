#!/bin/bash
set -e

PROJECT_ID="claw-platform-01"
REGION="us-central1"
REPO="openclaw-repo-prod"
IMAGE_NAME="openclaw-custom"
TAG="v1.0.0"

FULL_IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:${TAG}"

echo "Building Docker image: $FULL_IMAGE_NAME"
docker build --platform linux/amd64 -t "$FULL_IMAGE_NAME" .

echo "Pushing Docker image to Artifact Registry..."
docker push "$FULL_IMAGE_NAME"

echo "Done! Image available at: $FULL_IMAGE_NAME"
