#!/bin/bash

# 本地K8S环境部署脚本

set -e

# 配置参数 - 确保与configure-vault-k8s.sh和values.yaml中的配置一致
APP_NAME="cloudflare-app-example-app"
NAMESPACE="default"
LOCAL_PORT="8080"
SERVICE_PORT="80"

# Vault配置参数
VAULT_ADDR="http://192.168.2.50:8200"  # Vault服务器地址
VAULT_AUTH_METHOD="kubernetes"  # Vault认证方式：kubernetes 或 token
VAULT_K8S_ROLE="cloudflare-app-role"  # Kubernetes认证时的角色名称
# 如果使用token认证，取消下面这行注释并设置token值
# VAULT_TOKEN="your-vault-token"

# 创建命名空间
echo "创建命名空间..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 创建服务账户
echo "创建服务账户..."
kubectl create serviceaccount "${APP_NAME}" -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 提示Vault配置
echo "\nVault配置说明:"  
if [ "$VAULT_AUTH_METHOD" = "kubernetes" ]; then
  echo "1. 请确保Vault已配置Kubernetes认证方法"
  echo "2. 在Vault中创建对应的角色:'${VAULT_K8S_ROLE}'"  
  echo "3. 为角色绑定服务账户并设置适当的策略权限"
  echo ""
  echo "Vault角色创建示例命令："
  echo "vault write auth/kubernetes/role/${VAULT_K8S_ROLE} \
    bound_service_account_names=${APP_NAME} \
    bound_service_account_namespaces=${NAMESPACE} \
    policies=cloudflare-app-policy \
    ttl=1h \
    audience=vault"
  echo ""
elif [ "$VAULT_AUTH_METHOD" = "token" ]; then
  echo "1. 使用Token认证方式"
  echo "2. 请确保已在脚本中设置有效的VAULT_TOKEN或通过Kubernetes Secret提供"
  echo ""
  echo "如果需要使用Kubernetes Secret存储token，请运行："
  echo "kubectl create secret generic vault-token-secret \"
  echo "  --from-literal=token=your-vault-token \"
  echo "  -n ${NAMESPACE}"
  echo ""
  echo "并取消values.yaml中相关配置的注释"
  echo ""
fi
echo "请确保Vault策略已配置，允许访问以下路径："
echo "- secret/data/cloudflare"
echo "- secret/data/MY_CLOUDFLARE_EMAIL"
echo "- secret/data/MY_CLOUDFLARE_API_KEY"
echo ""
read -p "确认已完成Vault配置？按回车键继续或按Ctrl+C取消..."

# 检查镜像拉取密钥
echo "检查镜像拉取密钥..."
if ! kubectl get secret aliyun-acr-credentials -n "${NAMESPACE}" &> /dev/null; then
    echo "警告: 镜像拉取密钥 'aliyun-acr-credentials' 不存在，请确保已正确创建"
    echo "使用以下命令创建密钥："
    echo "kubectl create secret docker-registry aliyun-acr-credentials \\
  --docker-server=registry.cn-hangzhou.aliyuncs.com \\
  --docker-username=你的用户名 \\
  --docker-password=你的密码 \\
  --docker-email=your-email@example.com \\
  -n ${NAMESPACE}"
    # 暂停等待用户输入
    read -p "按回车键继续部署（不使用密钥）或按Ctrl+C取消..."
fi

# 部署应用
echo "部署应用..."
# 根据认证方式设置部署参数
deploy_params=(--namespace "${NAMESPACE}" --set image.tag=latest)

# 基本配置
deploy_params+=(--set env[0].value="${VAULT_ADDR}")
deploy_params+=(--set env[1].value="${VAULT_AUTH_METHOD}")

# Kubernetes认证配置
if [ "$VAULT_AUTH_METHOD" = "kubernetes" ]; then
  deploy_params+=(--set serviceAccount.create=false)
  deploy_params+=(--set serviceAccount.name="${APP_NAME}")
  deploy_params+=(--set env[2].value="${VAULT_K8S_ROLE}")
fi

# Token认证配置（如果已设置）
if [ "$VAULT_AUTH_METHOD" = "token" ] && [ -n "$VAULT_TOKEN" ]; then
  deploy_params+=(--set env[3].name="VAULT_TOKEN")
  deploy_params+=(--set env[3].value="${VAULT_TOKEN}")
fi

# 执行部署
echo "部署应用..."
helm upgrade --install "${APP_NAME}" ./charts/example-app "${deploy_params[@]}" --wait

# 等待Pod就绪
echo "等待Pod就绪..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="${APP_NAME}" -n "${NAMESPACE}" --timeout=300s

# 显示部署状态
echo "\n部署状态："
kubectl get pods -n "${NAMESPACE}"
kubectl get svc -n "${NAMESPACE}"
kubectl get sa -n "${NAMESPACE}"

echo "\n检查Vault连接状态："
echo "使用以下命令查看应用日志中的Vault连接信息："
echo "kubectl logs -l app.kubernetes.io/name=${APP_NAME} -n ${NAMESPACE} | grep VaultService"

# 启动port-forward
echo "\n启动Port-Forward (${LOCAL_PORT}:${SERVICE_PORT})..."
echo "访问地址: http://localhost:${LOCAL_PORT}"
echo "按 Ctrl+C 停止转发"
echo "\n"
kubectl port-forward svc/"${APP_NAME}" -n "${NAMESPACE}" "${LOCAL_PORT}:${SERVICE_PORT}"