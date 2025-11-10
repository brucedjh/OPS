# Vault Kubernetes Authentication - Troubleshooting Guide

This guide helps diagnose and resolve the "permission denied" error when authenticating to Vault using Kubernetes authentication.

## Table of Contents

1. [Common Causes](#common-causes)
2. [Using the Troubleshooting Script](#using-the-troubleshooting-script)
3. [Manual Verification Steps](#manual-verification-steps)
4. [Resolving Role Configuration Issues](#resolving-role-configuration-issues)
5. [Checking Kubernetes Auth Backend Configuration](#checking-kubernetes-auth-backend-configuration)
6. [Validating Service Account Permissions](#validating-service-account-permissions)

## Common Causes

The "permission denied" error during Kubernetes authentication typically occurs due to one of these reasons:

1. **Incorrect Role Configuration**: The Vault role is not properly bound to the service account or namespace
2. **Missing or Incorrect Kubernetes Auth Configuration**: The backend is not properly configured with the Kubernetes API server details
3. **Service Account Token Issues**: The token is invalid, expired, or not being properly passed
4. **Network Connectivity**: Vault cannot reach the Kubernetes API server
5. **Namespace Mismatch**: The role is configured for a different namespace

## Using the Troubleshooting Script

We've created a diagnostic script that can help identify common issues. Follow these steps to use it:

1. **Deploy the test pod** (if not already done):
   ```bash
   kubectl apply -f d:\code\cloudflare3\OPS\vault-test-pod.yaml
   ```

2. **Copy the troubleshooting script to the pod**:
   ```bash
   kubectl cp d:\code\cloudflare3\OPS\troubleshoot-vault-auth.sh vault-test-pod:/tmp/
   ```

3. **Make the script executable**:
   ```bash
   kubectl exec vault-test-pod -- chmod +x /tmp/troubleshoot-vault-auth.sh
   ```

4. **Run the script inside the pod**:
   ```bash
   kubectl exec -it vault-test-pod -- /tmp/troubleshoot-vault-auth.sh
   ```

5. **Review the output** for potential issues.

## Manual Verification Steps

### 1. Verify Service Account Exists

```bash
# Check if the service account exists
kubectl get sa cloudflare-app-example-app

# Get details about the service account
kubectl describe sa cloudflare-app-example-app
```

### 2. Verify Token is Available Inside Pod

```bash
# Exec into the test pod
kubectl exec -it vault-test-pod -- sh

# Verify token exists and has valid format
cat /var/run/secrets/kubernetes.io/serviceaccount/token

# Check namespace
cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
```

### 3. Check Vault Role Configuration

This requires admin access to Vault:

```bash
# List all Kubernetes roles
vault list auth/kubernetes/role

# Get details about our specific role
vault read auth/kubernetes/role/cloudflare-app
```

Verify these key settings:
- `bound_service_account_names` should include `cloudflare-app-example-app`
- `bound_service_account_namespaces` should include your namespace or be "*"
- `policies` should include the policy that grants access to the required secrets

## Resolving Role Configuration Issues

If the role is misconfigured, a Vault admin needs to update it:

```bash
# Example of updating the role with correct service account and namespace
vault write auth/kubernetes/role/cloudflare-app \
    bound_service_account_names=cloudflare-app-example-app \
    bound_service_account_namespaces=default \
    policies=cloudflare-app-policy \
    ttl=1h
```

## Checking Kubernetes Auth Backend Configuration

A Vault admin should verify the Kubernetes auth backend is properly configured:

```bash
# Check auth backend configuration
vault read auth/kubernetes/config
```

Key things to verify:
- `kubernetes_host` should point to the Kubernetes API server
- `kubernetes_ca_cert` should be valid
- `token_reviewer_jwt` should be valid and have proper permissions

## Validating Service Account Permissions

Ensure the service account has the necessary permissions in Kubernetes:

```bash
# Create a role binding if needed
cat > vault-auth-binding.yaml <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: vault-auth-rolebinding
  namespace: default
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: vault-auth-role
subjects:
- kind: ServiceAccount
  name: cloudflare-app-example-app
  namespace: default
EOF

# Apply the role binding
kubectl apply -f vault-auth-binding.yaml
```

## If All Else Fails

1. **Check Vault Server Logs**: Look for detailed error messages
2. **Verify Network Connectivity**: Ensure Vault can reach the Kubernetes API server
3. **Test with Root Token**: Temporarily use a root token to verify if the issue is with authentication or permissions
4. **Reconfigure from Scratch**: Use the `configure-vault-k8s.sh` script to reconfigure the Kubernetes auth backend

## Example Success Scenario

When authentication works correctly, you should see output like this:

```
Key                                       Value
---                                       -----
auth_type                                 kubernetes
token                                     s.vault-token-here
token_accessor                            accessor-here
token_duration                            1h
token_renewable                           true
token_policies                            [default cloudflare-app-policy]
identity_policies                         []
policies                                  [default cloudflare-app-policy]
token_meta_role                           cloudflare-app
token_meta_service_account_name           cloudflare-app-example-app
token_meta_service_account_namespace      default
token_meta_service_account_secret_name    
token_meta_service_account_uid            uid-here
```