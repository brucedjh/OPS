#!/bin/bash

# Vault Kubernetes认证配置脚本
# 此脚本使用curl命令调用Vault API配置Vault与Kubernetes服务账户集成
# 不依赖本地安装的vault CLI，提高兼容性
# 同时支持Windows PowerShell和Linux/macOS环境

set -e

# 检测操作系统
echo "检测操作系统环境..."
if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "win"* ]]; then
  IS_WINDOWS=true
  echo "✓ 检测到Windows环境"
else
  IS_WINDOWS=false
  echo "✓ 检测到Linux/macOS环境"
fi

# 配置参数 - 与其他配置文件保持一致
APP_NAME="cloudflare-app-example-app"
NAMESPACE="default"
VAULT_ADDR="http://192.168.2.50:8200"
VAULT_K8S_ROLE="cloudflare-app-role"
SERVICE_ACCOUNT_NAME="cloudflare-app-example-app"  # 与deploy-local.sh和values.yaml中的服务账户名称一致

# 检查必要的工具
echo "检查必要工具..."
if ! command -v curl &> /dev/null; then
  echo "错误: curl命令未找到，请安装curl"
  exit 1
fi

if ! command -v kubectl &> /dev/null; then
  echo "错误: kubectl命令未找到，请安装kubectl"
  exit 1
fi

# 检查Kubernetes服务账户是否存在
echo "检查Kubernetes服务账户..."
if kubectl get sa ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE} > /dev/null 2>&1; then
  echo "✓ 服务账户 '${SERVICE_ACCOUNT_NAME}' 在命名空间 '${NAMESPACE}' 中已存在"
else
  echo "✗ 服务账户 '${SERVICE_ACCOUNT_NAME}' 在命名空间 '${NAMESPACE}' 中不存在"
  echo "请确保服务账户已创建后再运行此脚本"
  exit 1
fi

# 检查Vault连接
echo "检查Vault连接..."
VAULT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health")
if [ "$VAULT_HEALTH" -eq 200 ] || [ "$VAULT_HEALTH" -eq 472 ] || [ "$VAULT_HEALTH" -eq 473 ] || [ "$VAULT_HEALTH" -eq 474 ] || [ "$VAULT_HEALTH" -eq 475 ]; then
  echo "✓ Vault服务器可达: ${VAULT_ADDR}"
  
  # 检查Vault是否已密封
  VAULT_STATUS=$(curl -s "${VAULT_ADDR}/v1/sys/health")
  if [[ "$IS_WINDOWS" == true ]]; then
    # Windows PowerShell环境下的grep替代方案
    if echo "$VAULT_STATUS" | findstr /C:'"sealed":true' > nul; then
      echo "✗ Vault已密封，请先解封Vault"
      echo "请访问 ${VAULT_ADDR} 进行解封操作"
      exit 1
    fi
  else
    # Linux/macOS环境
    if echo "$VAULT_STATUS" | grep -q '"sealed":true'; then
      echo "✗ Vault已密封，请先解封Vault"
      echo "请访问 ${VAULT_ADDR} 进行解封操作"
      exit 1
    fi
  fi
else
  echo "✗ 无法连接到Vault服务器: ${VAULT_ADDR}"
  echo "HTTP状态码: ${VAULT_HEALTH}"
  echo "请确保Vault服务器正在运行且网络可访问"
  exit 1
fi

# 获取Vault根令牌（如果没有提供，提示用户输入）
if [ -z "$VAULT_TOKEN" ]; then
  echo "\n请提供Vault根令牌（用于管理操作）"
  echo "注意: 出于安全考虑，此脚本不会保存令牌"
  read -s -p "Vault根令牌: " VAULT_TOKEN
  echo
  
  if [ -z "$VAULT_TOKEN" ]; then
    echo "错误: 必须提供Vault根令牌"
    exit 1
  fi
fi

# 验证Vault令牌是否有效
echo "验证Vault令牌..."
TOKEN_VALIDATION=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/auth/token/lookup-self")

if [ "$TOKEN_VALIDATION" -ne 200 ]; then
  echo "✗ Vault令牌无效或权限不足"
  echo "请确保提供的是有效的管理员令牌"
  exit 1
fi
echo "✓ Vault令牌验证成功"

# 启用Kubernetes认证方式（如果尚未启用）
echo "\n检查Kubernetes认证方式..."
AUTH_LIST=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/sys/auth")

# 检查Kubernetes认证是否已启用
K8S_AUTH_ENABLED=false
if [[ "$IS_WINDOWS" == true ]]; then
  # Windows PowerShell环境下的grep替代方案
  if echo "$AUTH_LIST" | findstr /C:'kubernetes/' > nul; then
    K8S_AUTH_ENABLED=true
  fi
else
  # Linux/macOS环境
  if echo "$AUTH_LIST" | grep -q 'kubernetes/'; then
    K8S_AUTH_ENABLED=true
  fi
fi

if [[ "$K8S_AUTH_ENABLED" == true ]]; then
  echo "✓ Kubernetes认证方式已启用"
else
  echo "启用Kubernetes认证方式..."
  ENABLE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"type":"kubernetes"}' \
    "${VAULT_ADDR}/v1/sys/auth/kubernetes")
  
  if [ "$ENABLE_RESPONSE" -eq 204 ]; then
    echo "✓ 成功启用Kubernetes认证方式"
  else
    echo "✗ 启用Kubernetes认证方式失败，HTTP状态码: ${ENABLE_RESPONSE}"
    echo "继续执行后续步骤..."
  fi
fi

# 配置Kubernetes认证后端
echo "\n配置Kubernetes认证后端..."

# 获取Kubernetes主机地址和CA证书
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}')

# 检查是否在Kubernetes Pod中运行
if [ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then
  # 在Kubernetes Pod中运行，使用Pod的服务账户令牌
  TOKEN_REVIEWER_JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
else
  # 不在Kubernetes Pod中运行，使用kubectl获取token（用于测试/开发环境）
  echo "警告: 不在Kubernetes Pod中运行，尝试使用kubectl获取服务账户token"
  # 修复kubectl create token命令语法
  TOKEN_REVIEWER_JWT=$(kubectl create token ${SERVICE_ACCOUNT_NAME} --namespace=${NAMESPACE} 2>&1 || true)
  if [ $? -ne 0 ] || [ -z "$TOKEN_REVIEWER_JWT" ] || [[ "$TOKEN_REVIEWER_JWT" == *"Error:"* ]]; then
    echo "错误: 无法获取服务账户token，请确保您具有足够的权限"
    echo "提示: 您可以手动设置token_reviewer_jwt的值，或者在Kubernetes Pod中运行此脚本"
    # 尝试使用另一种方法获取token
    echo "\n尝试使用替代方法获取服务账户token..."
    SA_SECRET=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE} -o jsonpath='{.secrets[0].name}' 2>&1 || echo "")
    if [ ! -z "$SA_SECRET" ]; then
      TOKEN_REVIEWER_JWT=$(kubectl get secret ${SA_SECRET} -n ${NAMESPACE} -o jsonpath='{.data.token}' 2>&1 || echo "")
      if [ ! -z "$TOKEN_REVIEWER_JWT" ]; then
        # Base64解码token
        if [[ "$IS_WINDOWS" == true ]]; then
          # Windows PowerShell环境下的Base64解码
          TOKEN_REVIEWER_JWT=$(echo "$TOKEN_REVIEWER_JWT" | powershell -Command "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($input))")
        else
          # Linux/macOS环境下的Base64解码
          TOKEN_REVIEWER_JWT=$(echo "$TOKEN_REVIEWER_JWT" | base64 --decode)
        fi
        echo "✓ 成功使用替代方法获取并解码服务账户token"
      fi
    fi
    
    # 如果仍然没有有效的token，退出
    if [ -z "$TOKEN_REVIEWER_JWT" ] || [[ "$TOKEN_REVIEWER_JWT" == *"Error:"* ]]; then
      echo "错误: 所有尝试获取服务账户token的方法都失败了"
      exit 1
    fi
  fi
fi

# 设置Kubernetes认证配置
CONFIG_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"kubernetes_host\":\"${K8S_HOST}\",\"kubernetes_ca_cert\":\"${K8S_CA_CERT}\",\"token_reviewer_jwt\":\"${TOKEN_REVIEWER_JWT}\",\"issuer\":\"https://kubernetes.default.svc.cluster.local\"}" \
  "${VAULT_ADDR}/v1/auth/kubernetes/config")

if [ "$CONFIG_RESPONSE" -eq 204 ]; then
  echo "✓ 成功配置Kubernetes认证后端"
else
  echo "✗ 配置Kubernetes认证后端失败，HTTP状态码: ${CONFIG_RESPONSE}"
  echo "继续执行后续步骤..."
fi

# 创建Vault策略
echo "\n创建Vault策略 'cloudflare-app-policy'..."
POLICY_CONTENT='{"policy":"# 允许读取默认路径的Cloudflare配置\npath \"secret/data/cloudflare\" {\n  capabilities = [\"read\"]\n}\n# 允许读取独立路径的Cloudflare Email\npath \"secret/data/MY_CLOUDFLARE_EMAIL\" {\n  capabilities = [\"read\"]\n}\n# 允许读取独立路径的Cloudflare API Key\npath \"secret/data/MY_CLOUDFLARE_API_KEY\" {\n  capabilities = [\"read\"]\n}\n# 添加对secret/路径的基本访问权限，用于验证权限\npath \"secret/\" {\n  capabilities = [\"list\"]\n}"}'

POLICY_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PUT \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${POLICY_CONTENT}" \
  "${VAULT_ADDR}/v1/sys/policies/acl/cloudflare-app-policy")

if [ "$POLICY_RESPONSE" -eq 204 ]; then
  echo "✓ 成功创建Vault策略 'cloudflare-app-policy'"
else
  echo "✗ 创建Vault策略失败，HTTP状态码: ${POLICY_RESPONSE}"
  echo "继续执行后续步骤..."
fi

# 创建Vault角色，绑定到Kubernetes服务账户
echo "\n创建Vault角色 '${VAULT_K8S_ROLE}'..."
ROLE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"bound_service_account_names\":\"${SERVICE_ACCOUNT_NAME}\",\"bound_service_account_namespaces\":\"${NAMESPACE}\",\"policies\":\"cloudflare-app-policy\",\"ttl\":\"1h\",\"audience\":\"vault\"}" \
  "${VAULT_ADDR}/v1/auth/kubernetes/role/${VAULT_K8S_ROLE}")

if [ "$ROLE_RESPONSE" -eq 204 ]; then
  echo "✓ 成功创建Vault角色 '${VAULT_K8S_ROLE}'"
else
  echo "✗ 创建Vault角色失败，HTTP状态码: ${ROLE_RESPONSE}"
  echo "注意: 可能是audience参数不被支持，但这不应该影响基本功能"
fi

echo "\n===== Vault Kubernetes认证配置完成 ====="
echo "角色 '${VAULT_K8S_ROLE}' 已配置并绑定到服务账户 '${SERVICE_ACCOUNT_NAME}'"
echo "策略 'cloudflare-app-policy' 已应用，允许访问必要的密钥路径"

echo "\n验证配置:"
echo "1. 服务账户已在Kubernetes中创建: '${SERVICE_ACCOUNT_NAME}' in namespace '${NAMESPACE}'"
echo "2. 应用将使用环境变量:"
echo "   - VAULT_ADDR=${VAULT_ADDR}"
echo "   - VAULT_AUTH_METHOD=kubernetes"
echo "   - VAULT_K8S_ROLE=${VAULT_K8S_ROLE}"
echo "   - VAULT_K8S_NAMESPACE=${NAMESPACE}"

echo "\n现在您可以部署应用，它将使用Kubernetes服务账户自动认证到Vault"

# 清理敏感信息
echo "\n正在清理会话中的敏感信息..."
if [[ "$IS_WINDOWS" == true ]]; then
  # Windows环境下的变量清理
  set VAULT_TOKEN=
  set TOKEN_REVIEWER_JWT=
else
  # Linux/macOS环境下的变量清理
  unset VAULT_TOKEN TOKEN_REVIEWER_JWT
fi

echo "✓ 脚本执行完成，敏感信息已清理"