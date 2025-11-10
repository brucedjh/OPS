#!/bin/bash

# Kubernetes Vault配置验证脚本

set -e

echo "===== Kubernetes Vault配置验证 ====="

# 配置参数
APP_NAME="cloudflare-app-example-app"
NAMESPACE="default"
VAULT_ADDR="http://192.168.2.50:8200"
VAULT_K8S_ROLE="cloudflare-app-role"

# 检查环境
echo "\n1. 检查Kubernetes环境..."
if ! kubectl get nodes &> /dev/null; then
  echo "❌ 无法连接到Kubernetes集群"
  echo "请确保kubectl已配置并可以访问集群"
  exit 1
fi
echo "✅ Kubernetes集群连接正常"

# 检查服务账户
echo "\n2. 检查服务账户..."
if kubectl get sa "${APP_NAME}" -n "${NAMESPACE}" &> /dev/null; then
  echo "✅ 服务账户 '${APP_NAME}' 在命名空间 '${NAMESPACE}' 中存在"
else
  echo "❌ 服务账户 '${APP_NAME}' 在命名空间 '${NAMESPACE}' 中不存在"
  echo "请运行 deploy-local.sh 创建服务账户"
  exit 1
fi

# 检查Vault连接
echo "\n3. 检查Vault连接..."
if command -v curl &> /dev/null; then
  if curl -s "${VAULT_ADDR}/v1/sys/health" | grep -q "initialized"; then
    echo "✅ Vault服务器可达: ${VAULT_ADDR}"
  else
    echo "❌ 无法连接到Vault服务器: ${VAULT_ADDR}"
    exit 1
  fi
else
  echo "⚠️ curl不可用，无法检查Vault连接"
fi

# 显示配置摘要
echo "\n===== 配置摘要 ====="
echo "应用名称: ${APP_NAME}"
echo "命名空间: ${NAMESPACE}"
echo "Vault地址: ${VAULT_ADDR}"
echo "Vault角色: ${VAULT_K8S_ROLE}"
echo "服务账户名称: ${APP_NAME}"
echo "======================\n"

echo "配置验证完成！所有配置项已统一。"
echo "请确保Vault已配置正确的角色和策略："
echo "1. 角色名称: ${VAULT_K8S_ROLE}"
echo "2. 绑定的服务账户: ${APP_NAME}"
echo "3. 绑定的命名空间: ${NAMESPACE}"
echo "4. 应用的策略: cloudflare-app-policy"
echo "\n建议执行: configure-vault-k8s.sh 脚本配置Vault"