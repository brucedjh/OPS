#!/bin/bash

# 简单的Vault Kubernetes认证测试脚本
set -e

echo "开始Vault Kubernetes认证测试..."
echo "====================================="

# 从values.yaml提取的配置参数
VAULT_ADDR="http://192.168.2.50:8200"
VAULT_K8S_ROLE="cloudflare-app-role"
SERVICE_ACCOUNT_NAME="cloudflare-app-example-app"
NAMESPACE="default"

echo "使用配置:"
echo "- 服务账户: ${SERVICE_ACCOUNT_NAME}"
echo "- 命名空间: ${NAMESPACE}"
echo "- Vault角色: ${VAULT_K8S_ROLE}"
echo "- Vault地址: ${VAULT_ADDR}"
echo "====================================="

# 创建测试Pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vault-test-pod
  namespace: ${NAMESPACE}
spec:
  serviceAccountName: ${SERVICE_ACCOUNT_NAME}
  containers:
  - name: vault-cli
    image: hashicorp/vault:latest
    command: ["sh", "-c", "sleep 3600"]
  restartPolicy: Never
EOF

echo "等待测试Pod启动..."
kubectl wait --for=condition=ready pod vault-test-pod -n ${NAMESPACE} --timeout=60s

echo "\n在测试Pod中执行Vault认证测试..."

# 在Pod中执行认证测试
echo "尝试使用Kubernetes服务账户令牌登录Vault..."
kubectl exec vault-test-pod -n ${NAMESPACE} -- sh -c " \
  export VAULT_ADDR=${VAULT_ADDR}; \
  echo '正在执行Vault Kubernetes认证...'; \
  AUTH_RESULT=$(vault write -field=token auth/kubernetes/login role=${VAULT_K8S_ROLE} jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) 2>&1); \
  if [ $? -eq 0 ]; then \
    echo '✓ Vault Kubernetes认证成功!'; \
    echo '\n测试使用获取的令牌访问Vault...'; \
    export VAULT_TOKEN=$AUTH_RESULT; \
    vault status; \
    echo '\n✓ 令牌有效，可以正常访问Vault!'; \
  else \
    echo '✗ Vault Kubernetes认证失败!'; \
    echo '错误详情: '; \
    echo $AUTH_RESULT; \
    exit 1; \
  fi \
"

echo "\n清理测试资源..."
kubectl delete pod vault-test-pod -n ${NAMESPACE} --grace-period=0 --force

echo "\n====================================="
echo "Vault Kubernetes认证测试完成!"
echo "====================================="