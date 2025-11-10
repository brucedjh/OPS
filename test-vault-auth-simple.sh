#!/bin/bash

# 简化版Vault认证测试脚本
# 适用于Windows环境和Kubernetes环境的Vault认证测试

echo "===== 简化版Vault认证测试 ====="

# 配置参数
APP_NAME="cloudflare-app-example-app"
NAMESPACE="default"
VAULT_ADDR="http://192.168.2.50:8200"
VAULT_K8S_ROLE="cloudflare-app-role"

export VAULT_ADDR

# 检测操作系统
if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "win"* ]]; then
  IS_WINDOWS=true
  echo "✓ 检测到Windows环境"
else
  IS_WINDOWS=false
  echo "✓ 检测到Linux/macOS环境"
fi

# 检查环境
echo "\n检查环境..."

# 检查必要的工具
echo "检查curl命令..."
if ! command -v curl &> /dev/null; then
    echo "❌ curl命令未找到，请安装curl"
    exit 1
fi

# Windows环境下的特殊处理
if [[ "$IS_WINDOWS" == true ]]; then
    echo "在Windows环境中运行，使用curl.exe..."
    CURL_CMD="curl.exe"
else
    CURL_CMD="curl"
fi

# 检查Vault服务器状态
echo "\n检查Vault服务器状态..."
HEALTH_RESPONSE=$($CURL_CMD -s "$VAULT_ADDR/v1/sys/health")

# 检查是否返回了有效的JSON
if [[ "$HEALTH_RESPONSE" == *"initialized"* ]]; then
    echo "✅ Vault服务器可达: $VAULT_ADDR"
    # 检查Vault是否已密封
    if [[ "$HEALTH_RESPONSE" == *'"sealed":false'* ]]; then
        echo "   ✅ Vault未密封"
    else
        echo "   ❌ Vault已密封，请先解封Vault"
        echo "   请访问 $VAULT_ADDR 进行解封操作"
        exit 1
    fi
else
    echo "❌ 无法连接到Vault服务器: $VAULT_ADDR"
    echo "错误响应: $HEALTH_RESPONSE"
    echo "请确保Vault服务器正在运行且网络可访问"
    exit 1
fi

# 检查是否在Kubernetes环境中
if [ -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then
    echo "\n检测到在Kubernetes Pod中运行"
    echo "将使用Kubernetes服务账户令牌进行认证测试"
    
    # 获取服务账户令牌
    SVC_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    
    # 测试Kubernetes认证
    echo "\n测试Kubernetes认证..."
    AUTH_RESPONSE=$($CURL_CMD -s -X POST "$VAULT_ADDR/v1/auth/kubernetes/login" \
        -H "Content-Type: application/json" \
        -d "{\"jwt\": \"$SVC_TOKEN\", \"role\": \"$VAULT_K8S_ROLE\"}")
    
    echo "认证响应: $AUTH_RESPONSE"
    
    if [[ "$AUTH_RESPONSE" == *'"client_token"'* ]]; then
        echo "✅ Kubernetes认证成功!"
        # 使用简单的字符串处理获取token（跨平台兼容）
        if [[ "$AUTH_RESPONSE" == *'"client_token":"'* ]]; then
            VAULT_TOKEN=$(echo "$AUTH_RESPONSE" | sed 's/.*"client_token":"\([^"]*\).*/\1/')
            
            # 测试读取Secret
            echo "\n测试读取Vault密钥..."
            SECRET_RESPONSE=$($CURL_CMD -s -X GET "$VAULT_ADDR/v1/secret/data/cloudflare" \
                -H "Authorization: Bearer $VAULT_TOKEN")
            
            echo "密钥读取响应: $SECRET_RESPONSE"
            
            if [[ "$SECRET_RESPONSE" == *'"data"'* ]]; then
                echo "✅ 成功读取Vault密钥!"
                echo "认证和授权配置正确"
            else
                echo "❌ 无法读取Vault密钥，可能权限不足"
                echo "请检查Vault策略配置"
            fi
        else
            echo "❌ 无法从认证响应中提取client_token"
        fi
    else
        echo "❌ Kubernetes认证失败"
        echo "错误详情: $AUTH_RESPONSE"
        echo "请检查Vault角色配置和服务账户权限"
    fi
else
    echo "\n在非Kubernetes环境中运行（可能是Windows）"
    echo "提供手动认证测试选项:"
    
    # 提示用户设置Vault令牌
    echo "\n1. 请确保已在Vault中登录并获取令牌"
    echo "   例如: vault login"
    echo "   或使用环境变量: export VAULT_TOKEN=your_token_here"
    
    # 提示用户使用token认证
    echo "\n2. 如果要在Windows上运行应用，请确保使用token认证模式:"
    echo "   在.env文件中设置: VAULT_AUTH_METHOD=token"
    echo "   并提供有效的VAULT_TOKEN值"
    
    # 测试连接和认证方法
    echo "\n测试连接到Vault..."
    echo "VAULT_ADDR: $VAULT_ADDR"
    echo "建议的VAULT_AUTH_METHOD: 在Windows上使用 'token'，在Kubernetes上使用 'kubernetes'"
    
    # 检查环境中是否有VAULT_TOKEN
    if [ -n "$VAULT_TOKEN" ]; then
        echo "\n检测到VAULT_TOKEN环境变量，测试token认证..."
        echo "使用token长度: ${#VAULT_TOKEN}"
        
        TOKEN_RESPONSE=$($CURL_CMD -s -X GET "$VAULT_ADDR/v1/auth/token/lookup-self" \
            -H "Authorization: Bearer $VAULT_TOKEN")
        
        echo "token验证响应: $TOKEN_RESPONSE"
        
        if [[ "$TOKEN_RESPONSE" == *'"client_token"'* ]]; then
            echo "✅ Token认证成功!"
            
            # 测试读取Secret
            echo "\n测试读取Vault密钥..."
            SECRET_RESPONSE=$($CURL_CMD -s -X GET "$VAULT_ADDR/v1/secret/data/cloudflare" \
                -H "Authorization: Bearer $VAULT_TOKEN")
            
            echo "密钥读取响应: $SECRET_RESPONSE"
            
            if [[ "$SECRET_RESPONSE" == *'"data"'* ]]; then
                echo "✅ 成功读取Vault密钥!"
                echo "token认证和授权配置正确"
            else
                echo "❌ 无法读取Vault密钥，可能权限不足"
                echo "请检查Vault策略配置"
                # 检查是否有权限错误
                if [[ "$SECRET_RESPONSE" == *'"permission denied"'* ]]; then
                    echo "错误: Vault返回权限被拒绝，请确保策略包含正确的路径权限"
                fi
            fi
        else
            echo "❌ Token认证失败"
            echo "请检查VAULT_TOKEN是否正确"
            # 检查常见错误
            if [[ "$TOKEN_RESPONSE" == *'"errors"'* ]]; then
                echo "错误详情: $TOKEN_RESPONSE"
            fi
        fi
    else
        echo "\n未检测到VAULT_TOKEN环境变量"
        echo "请使用 'export VAULT_TOKEN=your_token' 或在.env文件中设置"
        
        # 提供额外的故障排除建议
        echo "\n故障排除建议:"
        echo "1. 确保Vault服务器运行正常且未密封"
        echo "2. 验证VAULT_ADDR是否正确指向您的Vault服务器"
        echo "3. 检查您是否有正确的Vault管理员权限"
        echo "4. 确认已在Vault中创建了所需的策略和路径"
    fi
fi

echo "\n===== 测试完成 ===="
echo "如果测试失败，请检查以下几点:"
echo "1. Vault服务器是否正在运行且未密封"
echo "2. 认证方法配置是否正确"
echo "3. 服务账户权限或token是否有效"
echo "4. Vault策略是否正确配置了必要的访问权限"