# 解决Vault管理员权限问题

## 问题分析

当您尝试执行 `vault auth enable kubernetes` 命令时遇到 `permission denied` 错误，这表明您当前使用的Vault令牌没有足够的权限来启用新的认证方法。

在Vault中，启用认证方法需要 `sudo` 或 `root` 权限，这通常只有Vault的初始根令牌或具有管理员权限的策略才能执行。

## 解决方案

### 1. 使用Vault根令牌

如果您有Vault的初始根令牌（通常在Vault初始化过程中生成），请使用它来配置Kubernetes认证：

```bash
# 设置根令牌
export VAULT_TOKEN=your_root_token_here

# 然后启用Kubernetes认证
vault auth enable kubernetes

# 配置Kubernetes认证后端
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}')
\ vault write auth/kubernetes/config \
  kubernetes_host="${K8S_HOST}" \
  kubernetes_ca_cert="${K8S_CA_CERT}" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  issuer="https://kubernetes.default.svc.cluster.local"

# 创建策略和角色（与之前相同）
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

vault write auth/kubernetes/role/cloudflare-app \
  bound_service_account_names=cloudflare-app-example-app \
  bound_service_account_namespaces=default \
  policies=cloudflare-app-policy \
  ttl=1h
```

### 2. 使用管理员策略

如果您没有根令牌，但有创建新策略的权限，可以创建一个具有管理权限的策略并将其应用到一个新的令牌：

```bash
# 创建管理员策略
vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# 创建具有该策略的令牌
vault token create -policy=admin

# 使用新创建的管理员令牌
# export VAULT_TOKEN=new_admin_token
```

### 3. 直接使用配置脚本（推荐）

如果您有权限，可以使用我们的配置脚本，但需要使用管理员令牌运行：

```bash
# 设置管理员令牌
export VAULT_TOKEN=your_admin_token_here

# 运行配置脚本
/OPS/configure-vault-k8s.sh
```

## 安全注意事项

1. **根令牌保护**：根令牌具有最高权限，应谨慎使用并妥善保管
2. **最小权限原则**：配置完成后，建议使用只具有必要权限的令牌进行日常操作
3. **令牌轮换**：定期轮换所有Vault令牌以提高安全性

## 其他解决方案

如果您无法获取管理员权限，请联系您的系统管理员或Vault管理员，请求他们：

1. 启用Kubernetes认证方法
2. 配置Kubernetes认证后端
3. 创建所需的策略和角色

## 验证步骤

配置完成后，您可以返回到测试Pod并验证认证是否正常工作：

```bash
# 清除之前的管理员令牌（如果设置了）
unset VAULT_TOKEN

# 确保使用的是Pod的服务账户令牌
export VAULT_ADDR=http://192.168.2.50:8200
K8S_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# 测试认证
vault write auth/kubernetes/login role=cloudflare-app jwt=$K8S_TOKEN
```

如果认证成功，您应该能够看到带有令牌信息和策略的输出。