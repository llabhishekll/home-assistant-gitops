#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "====================================================="
echo "      Starting Ubuntu Server 26.04 GitOps Setup      "
echo "====================================================="
echo ""

# ---------------------------------------------------------
# Step 0: Gather User Input
# ---------------------------------------------------------
echo "Please provide your GitHub details to configure the watcher."
echo ""

read -p "Enter your GitHub Username: " GITHUB_USER
read -s -p "Enter your GitHub Personal Access Token (PAT): " GITHUB_TOKEN
echo "" # Add a newline after silent password input
read -p "Enter your Email: " GITHUB_EMAIL
read -p "Enter your GitHub Repository Name: " REPO_NAME
read -p "Enter the directory path in your repo for cluster configs [default: ./kubernetes/cluster]: " REPO_PATH

# Apply default path if the user leaves it blank
REPO_PATH=${REPO_PATH:-./kubernetes/cluster}

echo ""
echo "Configuration saved temporarily. Starting installation..."
echo "====================================================="

# ---------------------------------------------------------
# Step 1: Install K3s (The Engine)
# ---------------------------------------------------------
echo "[1/5] Installing K3s..."
# We disable the default Traefik installation to ensure port 80 
# remains completely free for your own customized ingress layer.
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --write-kubeconfig-mode 644

echo "Waiting for K3s to initialize (sleeping for 15 seconds)..."
sleep 15

# Verify K3s is running
echo "Checking node status:"
kubectl get nodes
echo "====================================================="

# Create the standard hidden .kube directory for user
mkdir -p ~/.kube

# Copy the K3s config file into that new directory
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Change the ownership of the file so user can use it
sudo chown $(id -u):$(id -g) ~/.kube/config

# ---------------------------------------------------------
# Step 2: Install Flux CLI (The Watcher's Tools)
# ---------------------------------------------------------
echo "[2/5] Installing Flux CLI..."
curl -s https://fluxcd.io/install.sh | sudo bash
echo "====================================================="

# ---------------------------------------------------------
# Step 3: Pre-flight Check
# ---------------------------------------------------------
echo "[3/5] Running Flux pre-flight checks..."
# This ensures K3s is fully ready to accept the Flux controllers
flux check --pre
echo "====================================================="

# ---------------------------------------------------------
# Step 4: Bootstrap the Cluster to GitHub
# ---------------------------------------------------------
echo "[4/5] Bootstrapping Flux to your GitHub repository..."

# Export the variables so the Flux CLI can pick them up
export GITHUB_TOKEN=$GITHUB_TOKEN
export GITHUB_USER=$GITHUB_USER

# Run the bootstrap command
# This installs Flux into K3s, creates the deploy key, and links it to GitHub
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$REPO_NAME \
  --branch=main \
  --path=$REPO_PATH \
  --personal \
  --components-extra=image-reflector-controller,image-automation-controller
echo "====================================================="

# ---------------------------------------------------------
# Step 5: Create GHCR Registry Secret
# ---------------------------------------------------------
echo "[5/5] Creating GHCR Docker Registry Secret..."

# Using dry-run and apply makes this idempotent (it will update safely if it already exists)
kubectl create secret docker-registry ghcr-login \
  --docker-server=ghcr.io \
  --docker-username="$GITHUB_USER" \
  --docker-password="$GITHUB_TOKEN" \
  --docker-email="$GITHUB_EMAIL" \
  --namespace=flux-system \
  --dry-run=client -o yaml | kubectl apply -f -

echo "====================================================="
echo " Setup Complete! "
echo "====================================================="
echo "Your server is now securely watching: $REPO_NAME at path $REPO_PATH."
echo "GHCR authentication secret 'ghcr-login' has been applied."
echo "To deploy or update applications, simply push changes to your GitHub repository."