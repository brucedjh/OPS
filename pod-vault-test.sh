#!/bin/bash

# Kubernetes Pod中Vault认证测试脚本
# 此脚本需要在已配置了正确服务账户的Pod内运行

set -e

echo "===== Pod内Vault认证测试脚本 ====="
echo "此脚本用于验证Pod中的服务账户是否能成功通过Kubernetes认证访问Vault"
echo "=================================="

# 配置参数
VAULT_ADDR=${VAULT_ADDR:-"http://192.168.2.50:8200"}
VAULT_K8S_ROLE=${VAULT_K8S_ROLE:-"cloudflare-app-role"}
K8S_TOKEN_PATH=${K8S_TOKEN_PATH:-"/var/run/secrets/kubernetes.io/serviceaccount/token"}
K8S_NAMESPACE_PATH=${K8S_NAMESPACE_PATH:-"/var/run/secrets/kubernetes.io/serviceaccount/namespace"}

# 显示配置信息
echo "\n配置信息:"
echo "- Vault地址: ${VAULT_ADDR}"
echo "- Vault Kubernetes角色: ${VAULT_K8S_ROLE}"
echo "- Kubernetes令牌路径: ${K8S_TOKEN_PATH}"

# 检查必要文件是否存在
if [ ! -f "${K8S_TOKEN_PATH}" ]; then
  echo "❌ 错误: 找不到Kubernetes服务账户令牌文件"
  echo "请确保此脚本在配置了正确服务账户的Kubernetes Pod中运行"
  exit 1
fi

# 读取命名空间
if [ -f "${K8S_NAMESPACE_PATH}" ]; then
  K8S_NAMESPACE=$(cat "${K8S_NAMESPACE_PATH}")
  echo "- 当前命名空间: ${K8S_NAMESPACE}"
fi

# 检查vault命令是否可用
echo "\n1. 检查vault命令..."
if command -v vault &> /dev/null; then
  echo "✅ vault命令可用"
else
  echo "❌ vault命令不可用，尝试安装..."
  # 尝试下载并安装vault客户端
  if command -v curl &> /dev/null; then
    echo "尝试下载vault客户端..."
    TEMP_DIR=$(mktemp -d)
    curl -L https://releases.hashicorp.com/vault/1.13.3/vault_1.13.3_linux_amd64.zip -o "${TEMP_DIR}/vault.zip"
    unzip "${TEMP_DIR}/vault.zip" -d "${TEMP_DIR}"
    mv "${TEMP_DIR}/vault" /usr/local/bin/
    chmod +x /usr/local/bin/vault
    if command -v vault &> /dev/null; then
      echo "✅ vault客户端安装成功"
    else
      echo "❌ vault客户端安装失败，请手动安装"
      exit 1
    fi
  else
    echo "❌ curl不可用，无法自动安装vault客户端"
    exit 1
  fi
fi

# 设置Vault地址
export VAULT_ADDR

# 测试1: 检查Vault连接
echo "\n2. 测试Vault连接..."
if vault status &> /dev/null; then
  echo "✅ Vault连接成功"
  # 显示Vault版本信息
  VAULT_VERSION=$(vault status -format=json | grep "version" | cut -d '"' -f 4 || echo "未知")
  echo "   Vault版本: ${VAULT_VERSION}"
else
  echo "❌ Vault连接失败"
  echo "请检查以下几点:"
  echo "1. Vault服务器地址是否正确: ${VAULT_ADDR}"
  echo "2. Vault服务是否正在运行"
  echo "3. Pod是否有网络访问权限"
  exit 1
fi

# 测试2: 尝试使用Kubernetes认证
echo "\n3. 测试Kubernetes认证..."
K8S_TOKEN=$(cat "${K8S_TOKEN_PATH}")
echo "正在尝试使用Kubernetes认证方式登录Vault..."

# 保存认证结果到临时文件
auth_result=$(mktemp)
auth_error=$(mktemp)

# 执行认证
echo "vault write auth/kubernetes/login role=${VAULT_K8S_ROLE} jwt=${K8S_TOKEN}"
vault write auth/kubernetes/login role=${VAULT_K8S_ROLE} jwt=${K8S_TOKEN} > "${auth_result}" 2> "${auth_error}"
auth_exit_code=$?

if [ ${auth_exit_code} -eq 0 ]; then
  echo "✅ Kubernetes认证成功!"
  
  # 提取令牌信息
  VAULT_TOKEN=$(grep "token " "${auth_result}" | awk '{print $2}')
  TOKEN_TTL=$(grep "ttl " "${auth_result}" | awk '{print $2}')
  
  if [ -n "${VAULT_TOKEN}" ]; then
    echo "   获得的Vault令牌: ${VAULT_TOKEN:0:10}..."
    echo "   令牌有效期: ${TOKEN_TTL}秒"
    # 设置令牌用于后续测试
    export VAULT_TOKEN
  else
    echo "   但无法提取Vault令牌信息"
  fi
else
  echo "❌ Kubernetes认证失败!"
  echo "错误详情:"
  cat "${auth_error}"
  echo "\n故障排除建议:"
  echo "1. 确认Vault角色 '${VAULT_K8S_ROLE}' 存在且配置正确"
  echo "2. 验证服务账户是否有权限使用此角色"
  echo "3. 检查服务账户和命名空间绑定是否正确"
  echo "4. 验证Vault Kubernetes认证方法是否已启用"
  
  # 清理临时文件
  rm -f "${auth_result}" "${auth_error}"
  exit 1
fi

# 清理临时文件
rm -f "${auth_result}" "${auth_error}"

# 测试3: 检查密钥访问权限
echo "\n4. 测试密钥访问权限..."

# 测试读取Cloudflare配置路径
echo "尝试读取Cloudflare配置..."

# 测试默认路径
echo "\n测试默认路径: secret/data/cloudflare"
if vault kv get secret/data/cloudflare &> /dev/null; then
  echo "✅ 成功访问默认路径: secret/data/cloudflare"
  # 显示部分内容（不显示敏感信息）
  vault kv get -format=json secret/data/cloudflare | grep -v "data" | grep -v "\[" | grep -v "\]" | grep -v "\\""
else
  echo "❌ 无法访问默认路径: secret/data/cloudflare"
  echo "错误: $(vault kv get secret/data/cloudflare 2>&1)"
fi

# 测试独立路径
echo "\n测试独立路径: secret/data/MY_CLOUDFLARE_EMAIL"
if vault kv get secret/data/MY_CLOUDFLARE_EMAIL &> /dev/null; then
  echo "✅ 成功访问独立路径: secret/data/MY_CLOUDFLARE_EMAIL"
else
  echo "❌ 无法访问独立路径: secret/data/MY_CLOUDFLARE_EMAIL"
  echo "错误: $(vault kv get secret/data/MY_CLOUDFLARE_EMAIL 2>&1)"
fi

echo "\n测试独立路径: secret/data/MY_CLOUDFLARE_API_KEY"
if vault kv get secret/data/MY_CLOUDFLARE_API_KEY &> /dev/null; then
  echo "✅ 成功访问独立路径: secret/data/MY_CLOUDFLARE_API_KEY"
else
  echo "❌ 无法访问独立路径: secret/data/MY_CLOUDFLARE_API_KEY"
  echo "错误: $(vault kv get secret/data/MY_CLOUDFLARE_API_KEY 2>&1)"
fi

# 测试4: 显示当前策略信息
echo "\n5. 显示当前策略信息..."
vault token capabilities secret/

# 总结
echo "\n=================================="
echo "Pod内Vault认证测试完成!"
echo "=================================="
echo "\n测试结果摘要:"
echo "1. Vault连接: ✅ 成功"
echo "2. Kubernetes认证: ✅ 成功"
echo "3. 密钥访问: 请查看上方测试结果"
echo "\n如果所有测试都通过，应用应该能够成功从Vault获取配置。"
echo "如果遇到权限错误，请检查Vault策略配置是否允许访问所需的密钥路径。"