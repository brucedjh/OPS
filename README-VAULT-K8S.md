# Vault-Kubernetes 配置指南

## 简介

本指南提供了使用 `configure-vault-k8s.sh` 脚本配置 Vault 与 Kubernetes 服务账户集成的详细说明。该脚本使用 curl 命令调用 Vault API，**不依赖**本地安装的 vault CLI 工具，提高了在各种环境中的兼容性。

## 脚本特点

- ✅ **无Vault CLI依赖**：使用标准curl命令完成所有操作
- ✅ **跨平台支持**：同时兼容Windows PowerShell和Linux/macOS环境
- ✅ **安全处理**：交互式输入Vault令牌，脚本结束时自动清理敏感信息
- ✅ **详细日志**：提供实时操作反馈和状态检查
- ✅ **错误处理**：全面的错误检测和友好的错误提示

## 环境要求

在运行脚本前，请确保您的环境已安装以下工具：

- **curl**：用于HTTP请求
- **kubectl**：用于Kubernetes集群操作，确保已正确配置集群访问权限
- **Kubernetes集群访问权限**：能够查看和创建服务账户令牌
- **Vault根令牌**：用于Vault管理操作（脚本会临时使用，不会保存）

## 配置参数

脚本中的关键配置参数已预设为：

- **应用名称**：`cloudflare-app-example-app`
- **命名空间**：`default`
- **Vault地址**：`http://192.168.2.50:8200`
- **Vault角色名称**：`cloudflare-app-role`
- **服务账户名称**：`cloudflare-app-example-app`

如需修改这些参数，请直接编辑脚本中的配置部分。

## 使用步骤

### 1. 准备工作

确保已创建Kubernetes服务账户：

```bash
# 如果还未创建服务账户，请先运行部署脚本
./deploy-local.sh
```

### 2. 运行配置脚本

直接执行脚本：

```bash
# 在Linux/macOS环境
chmod +x configure-vault-k8s.sh
./configure-vault-k8s.sh

# 在Windows PowerShell环境
./configure-vault-k8s.sh
```

### 3. 输入Vault根令牌

脚本会提示您输入Vault根令牌（出于安全考虑，输入不会显示在屏幕上）：

```
请提供Vault根令牌（用于管理操作）
注意: 出于安全考虑，此脚本不会保存令牌
Vault根令牌: **********
```

### 4. 验证配置

脚本执行完成后，会显示配置摘要和验证信息：

```
===== Vault Kubernetes认证配置完成 =====
角色 'cloudflare-app-role' 已配置并绑定到服务账户 'cloudflare-app-example-app'
策略 'cloudflare-app-policy' 已应用，允许访问必要的密钥路径

验证配置:
1. 服务账户已在Kubernetes中创建: 'cloudflare-app-example-app' in namespace 'default'
2. 应用将使用环境变量:
   - VAULT_ADDR=http://192.168.2.50:8200
   - VAULT_AUTH_METHOD=kubernetes
   - VAULT_K8S_ROLE=cloudflare-app-role
   - VAULT_K8S_NAMESPACE=default
```

## 排错指南

### 常见问题

1. **连接Vault失败**
   - 检查Vault服务器是否正在运行
   - 验证网络连接和防火墙设置
   - 确认Vault地址配置正确

2. **Vault已密封**
   - 访问Vault UI（http://192.168.2.50:8200）进行解封操作
   - 或使用Vault CLI解封：`vault operator unseal`

3. **Kubernetes认证配置失败**
   - 确认kubectl配置正确且具有足够权限
   - 检查服务账户是否存在且名称正确

4. **Vault令牌无效**
   - 确保使用的是有效的根令牌或具有管理员权限的令牌

### 验证连接

您可以使用以下命令测试应用是否能成功连接到Vault：

```bash
# 运行验证脚本
./test-vault-auth-simple.sh
```

## 最佳实践

- 定期更新Vault令牌和服务账户权限
- 生产环境中使用最小权限原则
- 避免在脚本中硬编码敏感信息
- 使用环境变量传递配置参数

## 支持的操作

脚本会自动执行以下操作：

1. 检查必要工具是否安装（curl、kubectl）
2. 验证Kubernetes服务账户是否存在
3. 检查Vault连接状态和密封状态
4. 验证Vault令牌有效性
5. 启用Kubernetes认证方式（如果尚未启用）
6. 配置Kubernetes认证后端
7. 创建必要的Vault策略
8. 配置Vault角色绑定到Kubernetes服务账户
9. 清理会话中的敏感信息

---

**注意**：本脚本用于配置目的，应在受信任的环境中运行。完成配置后，应用将使用Kubernetes服务账户自动认证到Vault，无需手动输入令牌。