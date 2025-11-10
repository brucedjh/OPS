#!/bin/bash

echo "===== Vault Kubernetes Authentication Troubleshooter ====="
echo "This script will help diagnose common issues with Vault Kubernetes auth"
echo "==========================================================="

# Set default values
VAULT_ADDR=${VAULT_ADDR:-"http://192.168.2.50:8200"}
VAULT_K8S_ROLE=${VAULT_K8S_ROLE:-"cloudflare-app-role"}  # 必须与应用配置和Vault策略中的角色名称一致
K8S_TOKEN_PATH=${K8S_TOKEN_PATH:-"/var/run/secrets/kubernetes.io/serviceaccount/token"}
K8S_NAMESPACE_PATH=${K8S_NAMESPACE_PATH:-"/var/run/secrets/kubernetes.io/serviceaccount/namespace"}

# Display configuration
echo "\nConfiguration:"
echo "- Vault Address: $VAULT_ADDR"
echo "- Vault Kubernetes Role: $VAULT_K8S_ROLE"
echo "- K8s Token Path: $K8S_TOKEN_PATH"

# Check if running inside a pod
if [ ! -f "$K8S_TOKEN_PATH" ]; then
  echo "\n❌ ERROR: Not running inside a Kubernetes pod or service account token not available"
  echo "Please run this script inside a properly configured Kubernetes pod"
  exit 1
fi

# Read namespace and service account info
K8S_NAMESPACE=$(cat "$K8S_NAMESPACE_PATH")
SERVICE_ACCOUNT_TOKEN=$(cat "$K8S_TOKEN_PATH")

# Check token format (basic validation)
if [[ ! "$SERVICE_ACCOUNT_TOKEN" =~ ^eyJ ]]; then
  echo "\n⚠️ WARNING: Service account token format looks unusual. This may be a token review token."
fi

echo "- Current Namespace: $K8S_NAMESPACE"
echo "- Service Account Token: [REDACTED] (length: ${#SERVICE_ACCOUNT_TOKEN} chars)"

# Check Vault connection
echo "\n1. Checking Vault connection..."
if vault status &> /dev/null; then
  echo "✅ Vault connection successful"
  VAULT_VERSION=$(vault status -format=json | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
  echo "   Vault Version: $VAULT_VERSION"
else
  echo "❌ Vault connection failed"
  echo "   Error: $(vault status 2>&1)"
  echo "   Please check network connectivity and Vault address"
  exit 1
fi

# Check if Kubernetes auth is enabled
echo "\n2. Checking if Kubernetes auth method is enabled..."
auth_methods=$(vault auth list -format=json 2>/dev/null || echo "{}")
if echo "$auth_methods" | grep -q 'kubernetes/'; then
  echo "✅ Kubernetes auth method is enabled"
else
  echo "❌ Kubernetes auth method is NOT enabled"
  echo "   Please enable it with: vault auth enable kubernetes"
  exit 1
fi

# Try to get role configuration (may fail due to permissions)
echo "\n3. Attempting to verify role configuration..."
role_config=$(vault read -format=json auth/kubernetes/role/$VAULT_K8S_ROLE 2>/dev/null || echo "{}")
if [[ "$role_config" != "{}" ]]; then
  echo "✅ Successfully retrieved role configuration"
  # Extract and display key configuration details without sensitive info
  bound_sa_names=$(echo "$role_config" | grep -o '"bound_service_account_names":"[^"]*"' | cut -d'"' -f4)
  bound_namespaces=$(echo "$role_config" | grep -o '"bound_service_account_namespaces":"[^"]*"' | cut -d'"' -f4)
  policies=$(echo "$role_config" | grep -o '"policies":[^]]*\]' | sed 's/"policies":\[//; s/\]//; s/"//g; s/, /, /g')
  
  echo "   Bound Service Accounts: $bound_sa_names"
  echo "   Bound Namespaces: $bound_namespaces"
  echo "   Policies: $policies"
  
  # Validate configuration
  if [[ ! "$bound_sa_names" == *"cloudflare-app-example-app"* ]]; then
    echo "⚠️ WARNING: Role is not bound to expected service account 'cloudflare-app-example-app'"
  fi
  if [[ ! "$bound_namespaces" == *"$K8S_NAMESPACE"* ]] && [[ "$bound_namespaces" != "*" ]]; then
    echo "⚠️ WARNING: Role is not bound to current namespace '$K8S_NAMESPACE'"
  fi
else
  echo "⚠️ Cannot retrieve role configuration (likely due to permissions)"
  echo "   This is normal if you don't have admin access to Vault"
fi

# Test authentication with debug info
echo "\n4. Testing Kubernetes authentication with debug info..."
set -x
export VAULT_ADDR
export K8S_TOKEN=$SERVICE_ACCOUNT_TOKEN
echo "Testing command: vault write auth/kubernetes/login role=$VAULT_K8S_ROLE jwt=$K8S_TOKEN"
vault write auth/kubernetes/login role=$VAULT_K8S_ROLE jwt=$K8S_TOKEN
set +x

echo "\n5. Common troubleshooting steps:"
echo "   a. Verify the Vault role '$VAULT_K8S_ROLE' exists and is correctly configured"
echo "   b. Ensure the role is bound to the service account 'cloudflare-app-example-app'"
echo "   c. Check that the role allows access from namespace '$K8S_NAMESPACE'"
echo "   d. Verify Kubernetes auth backend is properly configured with correct kubeconfig"
echo "   e. Check Vault server logs for more detailed error information"
echo "   f. Ensure the service account has the necessary RBAC permissions"

echo "\n==========================================================="
echo "Troubleshooting complete. Please check the output for potential issues."