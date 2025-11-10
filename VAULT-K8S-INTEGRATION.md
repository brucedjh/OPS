# Vault 与 Kubernetes 集成配置指南

## 概述

本文档详细说明如何配置 HashiCorp Vault 与 Kubernetes 服务账户集成，确保应用程序能够使用 Kubernetes 服务账户自动认证到 Vault，无需手动管理 Vault 令牌。

## 前提条件

- Kubernetes 集群已运行
- Vault 服务器已安装并可访问
- 已创建 Kubernetes 服务账户（`example-app-sa`）
- 已安装 `kubectl` 和 `vault` CLI 工具

## 配置步骤

### 1. 服务账户确认

首先确认 Kubernetes 中已存在服务账户 `cloudflare-app-example-app`：

```bash
kubectl get sa -n default
```

### 2. 配置 Vault Kubernetes 认证

#### 方法一：使用配置脚本（推荐）

我们提供了自动化脚本 `configure-vault-k8s.sh` 来简化配置过程：

```bash
# 赋予脚本执行权限
chmod +x OPS/configure-vault-k8s.sh

# 执行脚本
./OPS/configure-vault-k8s.sh
```

#### 方法二：手动配置步骤

如果需要手动配置，可以执行以下命令：

1. **启用 Kubernetes 认证方式**
   ```bash
   vault auth enable kubernetes
   ```

2. **配置 Kubernetes 认证后端**
   ```bash
   # 获取 Kubernetes 主机地址和 CA 证书
   K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
   K8S_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}')
   
   # 设置 Kubernetes 认证配置
   vault write auth/kubernetes/config \
     kubernetes_host="${K8S_HOST}" \
     kubernetes_ca_cert="${K8S_CA_CERT}" \
     token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
     issuer="https://kubernetes.default.svc.cluster.local"
   ```

3. **创建 Vault 策略**
   ```bash
   vault policy write cloudflare-app-policy - <<EOF
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
   ```

4. **创建 Vault 角色，绑定到 Kubernetes 服务账户**
   ```bash
   vault write auth/kubernetes/role/cloudflare-app \
     bound_service_account_names=cloudflare-app-example-app \
     bound_service_account_namespaces=default \
     policies=cloudflare-app-policy \
     ttl=1h \
     audience="kubernetes.default.svc"
   ```

   **注意：** 关于audience参数
   - audience参数用于增强JWT令牌验证的安全性
   - 如果收到关于audience的警告，这不会影响基本功能
   - 这是一个推荐配置但不是必需的

### 3. 在 Vault 中存储必要的密钥

使用以下命令在 Vault 中存储 Cloudflare 配置：

```bash
# 写入 Cloudflare 配置到 Vault
vault kv put secret/cloudflare \
  email="your_cloudflare_email@example.com" \
  api_key="your_cloudflare_api_key"

# 或者使用独立路径（如果应用配置为使用这些路径）
vault kv put secret/MY_CLOUDFLARE_EMAIL value="your_cloudflare_email@example.com"
vault kv put secret/MY_CLOUDFLARE_API_KEY value="your_cloudflare_api_key"
```

## 应用部署配置

确保应用部署时配置了以下环境变量：

- `VAULT_ADDR`: Vault 服务器地址（例如：`http://192.168.2.50:8200`）
- `VAULT_AUTH_METHOD`: 设置为 `kubernetes`
- `VAULT_K8S_ROLE`: 设置为 `cloudflare-app-role`
- `VAULT_K8S_NAMESPACE`: 设置为 `default`（可选，默认为 `default`）

部署脚本 `deploy-local.sh` 已经正确配置了这些环境变量。

## 工作原理

1. **服务账户令牌自动注入**：Kubernetes 会自动将服务账户令牌注入到 Pod 的文件系统中（路径：`/var/run/secrets/kubernetes.io/serviceaccount/token`）

2. **认证过程**：
   - 应用程序启动时，`vaultService.js` 会检测到 `VAULT_AUTH_METHOD=kubernetes`
   - 读取服务账户令牌
   - 发送认证请求到 Vault
   - Vault 验证令牌并检查服务账户名称 `cloudflare-app-example-app` 和命名空间 `default` 是否匹配
   - 验证通过后，Vault 返回临时访问令牌

3. **临时令牌使用**：应用使用返回的临时令牌访问 Vault 中的密钥

## 故障排除

### 常见问题及解决方案

1. **认证失败**
   - 检查 `bound_service_account_names` 是否正确设置为 `cloudflare-app-example-app`
   - 检查 `bound_service_account_namespaces` 是否正确设置为 `default`
   - 验证服务账户令牌是否可以被 Pod 访问
   - 注意：Vault 可能会显示关于未配置 audience 的警告，但这不影响功能

2. **权限被拒绝**
   - 确保已创建并应用 `cloudflare-app-policy` 策略
   - 检查策略中包含了所有必要的密钥路径

3. **连接问题**
   - 确保 Vault 服务地址正确且可从 Kubernetes 集群访问
   - 检查网络策略是否允许 Pod 访问 Vault 服务

### 验证步骤

1. **检查 Vault 角色配置**
   ```bash
   vault read auth/kubernetes/role/cloudflare-app
   ```

2. **检查策略配置**
   ```bash
   vault policy read cloudflare-app-policy
   ```

3. **检查应用日志**
   ```bash
   kubectl logs -l app.kubernetes.io/name=example-app -n default | grep VaultService
   ```

## 安全最佳实践

1. **最小权限原则**：确保策略只包含应用所需的最小权限
2. **短期令牌**：设置合理的 TTL（如 1 小时），定期轮换令牌
3. **监控审计**：启用 Vault 审计日志，监控对敏感信息的访问
4. **网络隔离**：限制对 Vault 服务的网络访问

## 总结

通过以上配置，Vault 将与现有的 Kubernetes 服务账户 `cloudflare-app-example-app` 保持一致，应用可以使用 Kubernetes 认证方式自动访问 Vault 中的密钥，无需手动管理 Vault 令牌，提高了安全性和部署的便利性。

**注意**：Vault 可能会显示关于未配置 audience 的警告，但这不影响功能正常工作。这只是一个安全增强建议。