#!/bin/bash

# 测试Vault Kubernetes认证集成脚本
# 此脚本用于验证Vault与Kubernetes服务账户的集成是否正常工作
set -e

# 配置参数
VAULT_ADDR="http://192.168.2.50:8200"
VAULT_K8S_ROLE="cloudflare-app-role"
SERVICE_ACCOUNT_NAME="cloudflare-app-example-app"
NAMESPACE="default"

# 设置环境变量
export VAULT_ADDR=${VAULT_ADDR}

echo "开始测试Vault Kubernetes认证集成..."
echo "====================================="
echo "服务账户: ${SERVICE_ACCOUNT_NAME}"
echo "命名空间: ${NAMESPACE}"
echo "Vault角色: ${VAULT_K8S_ROLE}"
echo "Vault地址: ${VAULT_ADDR}"
echo "====================================="

# 1. 检查Vault连接
echo "\n1. 检查Vault连接状态..."
if vault status > /dev/null 2>&1; then
  echo "✓ Vault连接正常"
else
  echo "✗ 无法连接到Vault服务器"
  echo "请确保Vault服务器正在运行且可访问"
  exit 1
fi

# 2. 检查Vault角色配置
 echo "\n2. 检查Vault角色配置..."
 if vault read auth/kubernetes/role/${VAULT_K8S_ROLE} > /dev/null 2>&1; then
   echo "✓ Vault角色 '${VAULT_K8S_ROLE}' 已存在"
   
   # 显示角色详细配置
   echo "\n角色配置详情:"
   vault read -format=json auth/kubernetes/role/${VAULT_K8S_ROLE} | grep -E 'bound_service_account_names|bound_service_account_namespaces'
 else
   echo "✗ Vault角色 '${VAULT_K8S_ROLE}' 不存在"
   echo "您看到此错误是因为Vault中缺少对应的角色配置。Vault角色是Kubernetes服务账户与Vault之间的必要连接。"
   echo "要解决此问题，请运行以下命令创建Vault角色:"
   echo "  ./configure-vault-k8s.sh"
   echo "\n重要说明:"
   echo "- 服务账户 '${SERVICE_ACCOUNT_NAME}' 已在Kubernetes中存在"
   echo "- 运行configure-vault-k8s.sh脚本将创建Vault角色并将其绑定到该服务账户"
   echo "- 这是Vault与Kubernetes集成的必要步骤"
   exit 1
 fi

# 3. 检查策略配置
echo "\n3. 检查策略配置..."
if vault policy read cloudflare-app-policy > /dev/null 2>&1; then
  echo "✓ 策略 'cloudflare-app-policy' 已存在"
  
  # 显示策略详情
  echo "\n策略详情:"
  vault policy read cloudflare-app-policy
else
  echo "✗ 策略 'cloudflare-app-policy' 不存在"
  echo "请使用 configure-vault-k8s.sh 脚本创建策略"
  exit 1
fi

# 4. 检查Kubernetes服务账户
echo "\n4. 检查Kubernetes服务账户..."
if kubectl get sa ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE} > /dev/null 2>&1; then
  echo "✓ 服务账户 '${SERVICE_ACCOUNT_NAME}' 在命名空间 '${NAMESPACE}' 中存在"
else
  echo "✗ 服务账户 '${SERVICE_ACCOUNT_NAME}' 在命名空间 '${NAMESPACE}' 中不存在"
  echo "请确保服务账户已创建"
  exit 1
fi

# 5. 创建测试Pod以验证认证
echo "\n5. 创建测试Pod以验证Vault认证..."

# 创建测试Pod YAML
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vault-auth-test
  namespace: ${NAMESPACE}
spec:
  serviceAccountName: ${SERVICE_ACCOUNT_NAME}
  containers:
  - name: vault-test
    image: hashicorp/vault:latest
    command: ["sh", "-c", "sleep 3600"]
  restartPolicy: Never
EOF

echo "等待测试Pod启动..."
kubectl wait --for=condition=ready pod vault-auth-test -n ${NAMESPACE} --timeout=60s

echo "\n6. 在测试Pod中验证Vault认证..."

# 在Pod中执行Vault认证测试
kubectl exec vault-auth-test -n ${NAMESPACE} -- sh -c " \
  export VAULT_ADDR=${VAULT_ADDR}; \
  echo '正在尝试使用Kubernetes认证...'; \
  vault write auth/kubernetes/login role=${VAULT_K8S_ROLE} jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); \
  if [ $? -eq 0 ]; then \
    echo '✓ Vault Kubernetes认证成功!'; \
  else \
    echo '✗ Vault Kubernetes认证失败!'; \
    exit 1; \
  fi \
"

# 清理测试Pod
echo "\n7. 清理测试Pod..."
kubectl delete pod vault-auth-test -n ${NAMESPACE} --grace-period=0 --force

echo "\n====================================="
echo "✅ Vault Kubernetes认证集成测试成功!"
echo "====================================="
echo "服务账户 '${SERVICE_ACCOUNT_NAME}' 可以成功认证到Vault角色 '${VAULT_K8S_ROLE}'"
echo "应用现在应该可以使用Kubernetes认证方式自动访问Vault中的密钥"