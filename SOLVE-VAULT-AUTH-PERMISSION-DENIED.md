# 解决Vault Kubernetes认证 "permission denied" 错误

## 问题分析

当您在执行 `vault write auth/kubernetes/login role=cloudflare-app jwt=$K8S_TOKEN` 命令时遇到 `permission denied` 错误，这通常表示Vault的Kubernetes认证配置有问题，或者角色绑定不正确。

## 解决方案步骤

### 1. 使用诊断脚本分析问题

首先，在您的测试Pod中运行我们的故障排除脚本以获取详细诊断信息：

```bash
# 确保脚本有执行权限
chmod +x /OPS/troubleshoot-vault-auth.sh

# 运行诊断脚本
/OPS/troubleshoot-vault-auth.sh
```

### 2. 重新配置Vault Kubernetes认证

如果诊断显示配置问题，请使用配置脚本重新设置Vault：

```bash
# 确保脚本有执行权限
chmod +x /OPS/configure-vault-k8s.sh

# 使用管理员权限运行配置脚本
# 注意：这需要在具有Vault管理员权限的环境中运行
/OPS/configure-vault-k8s.sh
```

### 3. 手动检查和修复（如果脚本无法解决）

如果自动脚本无法解决问题，请执行以下手动步骤：

#### 3.1 确认服务账户存在

```bash
kubectl get sa cloudflare-app-example-app -n default
```

#### 3.2 手动配置Vault Kubernetes认证

```bash
# 设置Vault地址
export VAULT_ADDR=http://192.168.2.50:8200

# 获取Kubernetes配置信息
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}')

# 重新配置Kubernetes认证后端
vault write auth/kubernetes/config \
  kubernetes_host="${K8S_HOST}" \
  kubernetes_ca_cert="${K8S_CA_CERT}" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  issuer="https://kubernetes.default.svc.cluster.local"

# 重新创建策略
vault policy write cloudflare-app-policy -
path "secret/data/cloudflare" {
  capabilities = ["read"]
}
path "secret/data/MY_CLOUDFLARE_EMAIL" {
  capabilities = ["read"]
}
path "secret/data/MY_CLOUDFLARE_API_KEY" {
  capabilities = ["read"]
}
EOF

# 重新创建角色
vault write auth/kubernetes/role/cloudflare-app \
  bound_service_account_names=cloudflare-app-example-app \
  bound_service_account_namespaces=default \
  policies=cloudflare-app-policy \
  ttl=1h
```

### 4. 验证修复

重新配置完成后，在测试Pod中验证认证：

```bash
# 设置Vault地址
export VAULT_ADDR=http://192.168.2.50:8200

# 读取服务账户令牌
K8S_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# 测试认证
vault write auth/kubernetes/login role=cloudflare-app jwt=$K8S_TOKEN
```

### 5. 常见问题解决

#### 问题1: 服务账户令牌问题
确保您的Pod正确挂载了服务账户令牌：

```bash
# 检查令牌文件是否存在
ls -la /var/run/secrets/kubernetes.io/serviceaccount/

# 检查令牌内容格式
head -c 10 /var/run/secrets/kubernetes.io/serviceaccount/token
```

#### 问题2: 角色绑定不匹配
确保Vault角色正确绑定到您的服务账户和命名空间：

```bash
# 使用管理员权限检查角色配置
vault read auth/kubernetes/role/cloudflare-app
```

检查输出中的 `bound_service_account_names` 和 `bound_service_account_namespaces` 是否与您的服务账户和命名空间匹配。

#### 问题3: 网络连接问题
确保Pod可以访问Vault服务器：

```bash
# 测试网络连接
telnet 192.168.2.50 8200

# 或使用curl
curl -v http://192.168.2.50:8200/v1/sys/health
```

## 成功验证

认证成功后，您应该看到类似以下输出：

```
Key                                       Value
---                                       -----
auth_type                                 kubernetes
token                                     s.vault-token-here
token_accessor                            accessor-here
token_duration                            1h
token_renewable                           true
token_policies                            [default cloudflare-app-policy]
identity_policies                         []
policies                                  [default cloudflare-app-policy]
token_meta_role                           cloudflare-app
token_meta_service_account_name           cloudflare-app-example-app
token_meta_service_account_namespace      default
```

## 后续步骤

如果认证成功，您可以继续测试密钥访问：

```bash
# 使用获取的令牌访问密钥
vault kv get secret/data/cloudflare
```

如果所有测试都通过，您的应用应该能够成功从Vault获取配置。