#!/bin/bash

# Vault Kubernetes认证故障排除与修复脚本
# 此脚本用于诊断并修复Vault Kubernetes认证中的"permission denied"错误
set -e

# 配置参数
VAULT_ADDR="http://192.168.2.50:8200"
VAULT_K8S_ROLE="cloudflare-app-role"
SERVICE_ACCOUNT_NAME="cloudflare-app-example-app"
NAMESPACE="default"

# 彩色输出函数
echo_info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

echo_success() {
  echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

echo_error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

echo_warning() {
  echo -e "\033[1;33m[WARNING]\033[0m $1"
}

# 检查必要工具
echo_info "检查必要工具..."
if ! command -v curl &> /dev/null; then
  echo_error "curl命令未找到，请安装curl"
  exit 1
fi

if ! command -v kubectl &> /dev/null; then
  echo_error "kubectl命令未找到，请安装kubectl"
  exit 1
fi

if ! command -v vault &> /dev/null; then
  echo_warning "vault CLI未找到，将使用curl进行API调用"
  USE_CURL=true
else
  echo_info "找到vault CLI，将优先使用vault命令"
  USE_CURL=false
fi

# 检查Kubernetes服务账户
echo_info "\n检查Kubernetes服务账户..."
if kubectl get sa ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE} > /dev/null 2>&1; then
  echo_success "服务账户 '${SERVICE_ACCOUNT_NAME}' 在命名空间 '${NAMESPACE}' 中存在"
  kubectl describe sa ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE}
else
  echo_error "服务账户 '${SERVICE_ACCOUNT_NAME}' 在命名空间 '${NAMESPACE}' 中不存在"
  echo_warning "正在创建服务账户..."
  kubectl create sa ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE}
  if [ $? -eq 0 ]; then
    echo_success "成功创建服务账户"
  else
    echo_error "创建服务账户失败，请手动创建"
  fi
fi

# 检查Vault连接
echo_info "\n检查Vault连接..."
if [ "$USE_CURL" = true ]; then
  VAULT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health")
  if [ "$VAULT_HEALTH" -eq 200 ] || [ "$VAULT_HEALTH" -eq 472 ] || [ "$VAULT_HEALTH" -eq 473 ] || [ "$VAULT_HEALTH" -eq 474 ] || [ "$VAULT_HEALTH" -eq 475 ]; then
    echo_success "Vault服务器可达: ${VAULT_ADDR}"
  else
    echo_error "无法连接到Vault服务器: ${VAULT_ADDR}"
    echo_error "HTTP状态码: ${VAULT_HEALTH}"
    exit 1
  fi
else
  if vault status > /dev/null 2>&1; then
    echo_success "Vault连接正常: ${VAULT_ADDR}"
  else
    echo_error "无法连接到Vault服务器: ${VAULT_ADDR}"
    exit 1
  fi
fi

# 获取Vault根令牌
echo_info "\n请提供Vault根令牌以进行管理操作"
echo_warning "注意: 出于安全考虑，此脚本不会保存令牌"
read -s -p "Vault根令牌: " VAULT_TOKEN
echo

export VAULT_TOKEN

# 验证Vault令牌
echo_info "\n验证Vault令牌..."
if [ "$USE_CURL" = true ]; then
  TOKEN_VALIDATION=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/auth/token/lookup-self")
  
  if [ "$TOKEN_VALIDATION" -ne 200 ]; then
    echo_error "Vault令牌无效或权限不足"
    exit 1
  fi
else
  if ! vault token lookup > /dev/null 2>&1; then
    echo_error "Vault令牌无效或权限不足"
    exit 1
  fi
fi
echo_success "Vault令牌验证成功"

# 检查并启用Kubernetes认证
echo_info "\n检查Kubernetes认证方式..."
if [ "$USE_CURL" = true ]; then
  AUTH_LIST=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/sys/auth")
  if [[ "$AUTH_LIST" == *"kubernetes/"* ]]; then
    echo_success "Kubernetes认证方式已启用"
  else
    echo_warning "启用Kubernetes认证方式..."
    curl -s -o /dev/null \
      -X POST \
      -H "X-Vault-Token: ${VAULT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"type":"kubernetes"}' \
      "${VAULT_ADDR}/v1/sys/auth/kubernetes"
    echo_success "成功启用Kubernetes认证方式"
  fi
else
  if vault auth list | grep -q 'kubernetes/'; then
    echo_success "Kubernetes认证方式已启用"
  else
    echo_warning "启用Kubernetes认证方式..."
    vault auth enable kubernetes
    echo_success "成功启用Kubernetes认证方式"
  fi
fi

# 重新配置Kubernetes认证后端
echo_info "\n重新配置Kubernetes认证后端..."

# 获取Kubernetes主机地址和CA证书
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}')

# 获取服务账户令牌
echo_info "获取服务账户令牌..."
SA_SECRET=$(kubectl get serviceaccount ${SERVICE_ACCOUNT_NAME} -n ${NAMESPACE} -o jsonpath='{.secrets[0].name}' 2>&1 || echo "")
if [ ! -z "$SA_SECRET" ]; then
  TOKEN_REVIEWER_JWT=$(kubectl get secret ${SA_SECRET} -n ${NAMESPACE} -o jsonpath='{.data.token}' 2>&1 || echo "")
  if [ ! -z "$TOKEN_REVIEWER_JWT" ]; then
    # Base64解码token
    if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "win"* ]]; then
      # Windows环境
      TOKEN_REVIEWER_JWT=$(echo "$TOKEN_REVIEWER_JWT" | powershell -Command "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($input))")
    else
      # Linux/macOS环境
      TOKEN_REVIEWER_JWT=$(echo "$TOKEN_REVIEWER_JWT" | base64 --decode)
    fi
    echo_success "成功获取并解码服务账户token"
  fi
fi

if [ -z "$TOKEN_REVIEWER_JWT" ]; then
  echo_warning "使用替代方法获取服务账户token..."
  TOKEN_REVIEWER_JWT=$(kubectl create token ${SERVICE_ACCOUNT_NAME} --namespace=${NAMESPACE} 2>&1 || true)
  if [ $? -ne 0 ] || [ -z "$TOKEN_REVIEWER_JWT" ] || [[ "$TOKEN_REVIEWER_JWT" == *"Error:"* ]]; then
    echo_error "无法获取服务账户token，请确保您具有足够的权限"
    exit 1
  fi
fi

# 配置Kubernetes认证后端
if [ "$USE_CURL" = true ]; then
  echo_info "使用curl配置Kubernetes认证后端..."
  CONFIG_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"kubernetes_host\":\"${K8S_HOST}\",\"kubernetes_ca_cert\":\"${K8S_CA_CERT}\",\"token_reviewer_jwt\":\"${TOKEN_REVIEWER_JWT}\",\"issuer\":\"https://kubernetes.default.svc.cluster.local\"}" \
    "${VAULT_ADDR}/v1/auth/kubernetes/config")
  
  if [ "$CONFIG_RESPONSE" -eq 204 ]; then
    echo_success "成功配置Kubernetes认证后端"
  else
    echo_error "配置Kubernetes认证后端失败，HTTP状态码: ${CONFIG_RESPONSE}"
  fi
else
  echo_info "使用vault命令配置Kubernetes认证后端..."
  vault write auth/kubernetes/config \
    kubernetes_host="${K8S_HOST}" \
    kubernetes_ca_cert=@<(echo "${K8S_CA_CERT}" | base64 --decode) \
    token_reviewer_jwt="${TOKEN_REVIEWER_JWT}" \
    issuer="https://kubernetes.default.svc.cluster.local"
  echo_success "成功配置Kubernetes认证后端"
fi

# 创建或更新Vault策略
echo_info "\n创建或更新Vault策略 'cloudflare-app-policy'..."
POLICY_CONTENT='# 允许读取默认路径的Cloudflare配置
path "secret/data/cloudflare" {
  capabilities = ["read"]
}
# 允许读取独立路径的Cloudflare Email
path "secret/data/MY_CLOUDFLARE_EMAIL" {
  capabilities = ["read"]
}
# 允许读取独立路径的Cloudflare API Key
path "secret/data/MY_CLOUDFLARE_API_KEY" {
  capabilities = ["read"]
}
# 添加对secret/路径的基本访问权限，用于验证权限
path "secret/" {
  capabilities = ["list"]
}'

if [ "$USE_CURL" = true ]; then
  # 转义JSON字符串
  ESCAPED_POLICY=$(echo "$POLICY_CONTENT" | sed 's/"/\\"/g' | sed 's/$/\\n/g' | tr -d '\n')
  POLICY_JSON="{\"policy\":\"${ESCAPED_POLICY}\"}"
  
  POLICY_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${POLICY_JSON}" \
    "${VAULT_ADDR}/v1/sys/policies/acl/cloudflare-app-policy")
  
  if [ "$POLICY_RESPONSE" -eq 204 ]; then
    echo_success "成功创建或更新Vault策略 'cloudflare-app-policy'"
  else
    echo_error "创建Vault策略失败，HTTP状态码: ${POLICY_RESPONSE}"
  fi
else
  echo "$POLICY_CONTENT" | vault policy write cloudflare-app-policy -
  echo_success "成功创建或更新Vault策略 'cloudflare-app-policy'"
fi

# 创建或更新Vault角色
echo_info "\n创建或更新Vault角色 '${VAULT_K8S_ROLE}'..."
if [ "$USE_CURL" = true ]; then
  ROLE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"bound_service_account_names\":\"${SERVICE_ACCOUNT_NAME}\",\"bound_service_account_namespaces\":\"${NAMESPACE}\",\"policies\":\"cloudflare-app-policy\",\"ttl\":\"1h\",\"audience\":\"vault\"}" \
    "${VAULT_ADDR}/v1/auth/kubernetes/role/${VAULT_K8S_ROLE}")
  
  if [ "$ROLE_RESPONSE" -eq 204 ]; then
    echo_success "成功创建或更新Vault角色 '${VAULT_K8S_ROLE}'"
  else
    echo_error "创建Vault角色失败，HTTP状态码: ${ROLE_RESPONSE}"
  fi
else
  vault write auth/kubernetes/role/${VAULT_K8S_ROLE} \
    bound_service_account_names="${SERVICE_ACCOUNT_NAME}" \
    bound_service_account_namespaces="${NAMESPACE}" \
    policies="cloudflare-app-policy" \
    ttl="1h" \
    audience="vault"
  echo_success "成功创建或更新Vault角色 '${VAULT_K8S_ROLE}'"
fi

# 验证角色配置
echo_info "\n验证Vault角色配置..."
if [ "$USE_CURL" = true ]; then
  ROLE_CONFIG=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/auth/kubernetes/role/${VAULT_K8S_ROLE}")
  echo "角色配置:"
  echo "$ROLE_CONFIG" | grep -E 'bound_service_account_names|bound_service_account_namespaces|policies'
else
  echo "角色配置:"
  vault read auth/kubernetes/role/${VAULT_K8S_ROLE}
fi

# 创建测试Pod进行验证
echo_info "\n创建测试Pod进行认证验证..."

# 删除可能存在的旧测试Pod
if kubectl get pod vault-auth-test -n ${NAMESPACE} > /dev/null 2>&1; then
  echo_warning "删除已存在的测试Pod..."
  kubectl delete pod vault-auth-test -n ${NAMESPACE} --grace-period=0 --force > /dev/null 2>&1
fi

# 创建新的测试Pod
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

echo_info "等待测试Pod启动（最多120秒）..."
kubectl wait --for=condition=ready pod vault-auth-test -n ${NAMESPACE} --timeout=120s

# 执行认证测试
echo_info "\n执行Vault Kubernetes认证测试..."
AUTH_RESULT=$(kubectl exec vault-auth-test -n ${NAMESPACE} -- sh -c " \
  export VAULT_ADDR=${VAULT_ADDR}; \
  vault write -field=token auth/kubernetes/login role=${VAULT_K8S_ROLE} jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) 2>&1 || echo 'AUTH_FAILED' \
")

if [[ "$AUTH_RESULT" == *"AUTH_FAILED"* ]]; then
  echo_error "Vault Kubernetes认证测试失败"
  echo_warning "尝试使用详细模式再次测试..."
  kubectl exec vault-auth-test -n ${NAMESPACE} -- sh -c " \
    export VAULT_ADDR=${VAULT_ADDR}; \
    echo 'Debug Info:'; \
    echo 'Namespace: $(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)'; \
    echo 'Token Exists: $(test -f /var/run/secrets/kubernetes.io/serviceaccount/token && echo YES || echo NO)'; \
    echo 'Trying auth...'; \
    vault write -v auth/kubernetes/login role=${VAULT_K8S_ROLE} jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) \
  "
else
  echo_success "Vault Kubernetes认证测试成功!"
  echo_info "获取到的令牌: ${AUTH_RESULT:0:20}..."
fi

# 清理测试Pod
echo_info "\n清理测试Pod..."
kubectl delete pod vault-auth-test -n ${NAMESPACE} --grace-period=0 --force

# 清理敏感信息
echo_info "\n清理会话中的敏感信息..."
export VAULT_TOKEN=""

if [[ "$AUTH_RESULT" != *"AUTH_FAILED"* ]]; then
  echo_success "\n✅ 修复完成！Vault Kubernetes认证现在应该可以正常工作了"
  echo_info "服务账户 '${SERVICE_ACCOUNT_NAME}' 已成功绑定到Vault角色 '${VAULT_K8S_ROLE}'"
  echo_info "应用现在应该可以使用Kubernetes认证方式自动访问Vault中的密钥"
else
  echo_error "\n❌ 修复尝试完成，但认证测试仍然失败"
  echo_warning "请检查以下几点："
  echo_warning "1. Vault服务器是否正常运行且未密封"
  echo_warning "2. Kubernetes API服务器是否可从Vault服务器访问"
  echo_warning "3. 服务账户 '${SERVICE_ACCOUNT_NAME}' 是否在正确的命名空间中"
  echo_warning "4. Vault角色 '${VAULT_K8S_ROLE}' 的配置是否正确"
  echo_warning "5. 尝试查看Vault服务器日志获取更多详细错误信息"
fi