#!/bin/bash

# Vault环境检查脚本
# 用于检查Vault设置和连接

echo "===== Vault环境检查 ====="

# 检查Vault CLI
if command -v vault &> /dev/null; then
    echo "✅ Vault CLI已安装"
    VAULT_VERSION=$(vault version)
    echo "   版本: $VAULT_VERSION"
else
    echo "❌ Vault CLI未安装"
    echo "   请从 https://developer.hashicorp.com/vault/install 下载并安装Vault CLI"
    echo "   安装后确保将vault可执行文件添加到系统PATH中"
    exit 1
fi

# 检查Kubectl
if command -v kubectl &> /dev/null; then
    echo "✅ Kubectl已安装"
    KUBE_VERSION=$(kubectl version --client --short)
    echo "   版本: $KUBE_VERSION"
else
    echo "❌ Kubectl未安装"
    echo "   请安装kubectl以与Kubernetes集群交互"
    exit 1
fi

# 检查Kubernetes连接
echo "\n检查Kubernetes连接..."
if kubectl get nodes &> /dev/null; then
    echo "✅ Kubernetes集群连接正常"
    KUBE_CONTEXT=$(kubectl config current-context)
    echo "   当前上下文: $KUBE_CONTEXT"
else
    echo "❌ 无法连接到Kubernetes集群"
    echo "   请确保kubectl已正确配置"
    exit 1
fi

# 检查Vault连接
echo "\n检查Vault连接..."
VAULT_ADDR="http://192.168.2.50:8200"
export VAULT_ADDR

if vault status &> /dev/null; then
    echo "✅ Vault服务器连接正常: $VAULT_ADDR"
    # 检查Vault是否已初始化和未密封
    VAULT_STATUS=$(vault status -format=json)
    if echo "$VAULT_STATUS" | grep -q '"initialized":true'; then
        echo "   ✅ Vault已初始化"
    else
        echo "   ❌ Vault未初始化"
    fi
    if echo "$VAULT_STATUS" | grep -q '"sealed":false'; then
        echo "   ✅ Vault未密封"
    else
        echo "   ❌ Vault已密封"
    fi
else
    echo "❌ 无法连接到Vault服务器: $VAULT_ADDR"
    echo "   请检查Vault服务器是否正在运行且网络可访问"
    echo "   尝试使用浏览器访问: $VAULT_ADDR"
    exit 1
fi

# 检查Vault认证方法
echo "\n检查Vault认证方法..."
if vault auth list | grep -q 'kubernetes/'; then
    echo "✅ Kubernetes认证方法已启用"
else
    echo "⚠️ Kubernetes认证方法未启用"
    echo "   将在运行configure-vault-k8s.sh时启用"
fi

# 检查Vault角色
echo "\n检查Vault角色..."
VAULT_K8S_ROLE="cloudflare-app-role"
if vault read auth/kubernetes/role/$VAULT_K8S_ROLE &> /dev/null; then
    echo "✅ Vault角色 '$VAULT_K8S_ROLE' 已存在"
else
    echo "⚠️ Vault角色 '$VAULT_K8S_ROLE' 不存在"
    echo "   将在运行configure-vault-k8s.sh时创建"
fi

# 检查Vault策略
echo "\n检查Vault策略..."
VAULT_POLICY="cloudflare-app-policy"
if vault policy read $VAULT_POLICY &> /dev/null; then
    echo "✅ Vault策略 '$VAULT_POLICY' 已存在"
else
    echo "⚠️ Vault策略 '$VAULT_POLICY' 不存在"
    echo "   将在运行configure-vault-k8s.sh时创建"
fi

echo "\n===== 环境检查完成 ====="
echo "所有必要的工具和连接都已验证"
echo "您现在可以运行 configure-vault-k8s.sh 来配置Vault"