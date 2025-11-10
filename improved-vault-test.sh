#!/bin/bash

# 改进版Vault Kubernetes认证测试脚本
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

# 首先检查并删除已存在的测试Pod
echo "检查并删除已存在的测试Pod..."
kubectl delete pod vault-test-pod -n ${NAMESPACE} --grace-period=0 --force 2>/dev/null || true

# 等待几秒钟确保Pod被完全删除
sleep 3

# 创建新的测试Pod
echo "创建新的测试Pod..."
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
echo "(增加超时时间到120秒)"

# 使用更长的超时时间，如果失败则显示Pod状态信息
if ! kubectl wait --for=condition=ready pod vault-test-pod -n ${NAMESPACE} --timeout=120s; then
  echo "\nPod启动失败，显示Pod详细信息:"
  kubectl describe pod vault-test-pod -n ${NAMESPACE}
  kubectl get pod vault-test-pod -n ${NAMESPACE}
  exit 1
fi

echo "\nPod启动成功，在测试Pod中执行Vault认证测试..."

# 在Pod中执行认证测试
echo "尝试使用Kubernetes服务账户令牌登录Vault..."
kubectl exec vault-test-pod -n ${NAMESPACE} -- sh -c " \
  export VAULT_ADDR=${VAULT_ADDR}; \
  echo '正在检查Vault连接...'; \
  if vault status > /dev/null 2>&1; then \
    echo '✓ Vault服务连接正常'; \
  else \
    echo '✗ 无法连接到Vault服务'; \
    echo '检查Vault地址或网络连接'; \
    exit 1; \
  fi; \
  \
  echo '\n正在执行Vault Kubernetes认证...'; \
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

# 清理部分使用单独的错误处理，即使认证失败也会清理资源
echo "\n清理测试资源..."
kubectl delete pod vault-test-pod -n ${NAMESPACE} --grace-period=0 --force

echo "\n====================================="
echo "Vault Kubernetes认证测试完成!"
echo "====================================="