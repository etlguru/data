#!/bin/bash

# Exit on any error
set -e

# Variables
PROJECT_DIR="$(pwd)"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
VARS_FILE="$PROJECT_DIR/vars.json"
RDS_ENDPOINT="cdc-source-db.codgiciuo3w4.us-east-1.rds.amazonaws.com"
RDS_USER="cdcuser"
RDS_DB="cdc_db"
DOCKER_IMAGE="postgres:latest"

# Step 1: Initialize Terraform
echo "Initializing Terraform..."
cd "$TERRAFORM_DIR"
terraform init

# Step 2: Apply Terraform configuration (RDS only)
echo "Applying Terraform configuration for RDS..."
terraform apply -auto-approve -var-file="$VARS_FILE" -target=aws_db_instance.source

# Step 3: Pull Docker image
echo "Pulling Docker image: $DOCKER_IMAGE..."
docker pull "$DOCKER_IMAGE"

# Step 4: Connect to RDS using Docker
echo "Connecting to RDS instance at $RDS_ENDPOINT..."
docker run -it --rm "$DOCKER_IMAGE" psql -h "$RDS_ENDPOINT" -U "$RDS_USER" -d "$RDS_DB"

echo "Done!"