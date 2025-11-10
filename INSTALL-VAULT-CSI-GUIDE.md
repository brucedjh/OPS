# Vault CSI Provider 和 SecretProviderClass 安装指南

## 问题描述

当尝试部署应用时，遇到错误：
```
secrets-store.csi.x-k8s.io/SecretProviderClass "default/cloudflare-vault-provider" not found
```

这表明 Kubernetes 集群中缺少必要的 SecretProviderClass CRD 资源和相关组件。

## 解决方案

需要在 Kubernetes 集群中安装以下组件：

1. SecretProviderClass CRD
2. Secrets Store CSI Driver
3. Vault CSI Provider

## 安装步骤

### 1. 安装 CSIDriver

```bash
# 安装 CSIDriver
kubectl apply -f ./csidriver.yaml
```

### 2. 安装 SecretProviderClass CRDs

```bash
# 安装 SecretProviderClass CRD
kubectl apply -f ./secretproviderclass-crd.yaml

# 安装 SecretProviderClassPodStatus CRD
kubectl apply -f ./secretproviderclasspodstatus-crd.yaml
```

### 3. 安装 Secrets Store CSI Driver

```bash
# 安装 Secrets Store CSI Driver
kubectl apply -f ./secrets-store-csi-driver.yaml
```

### 4. 安装 Vault CSI Provider

```bash
# 安装 Vault CSI Provider RBAC
kubectl apply -f ./vault-csi-provider-rbac.yaml

# 安装 Vault CSI Provider
kubectl apply -f ./vault-csi-provider.yaml
```

### 4. 验证安装

```bash
# 验证 CRD 安装
kubectl get crd | grep secret

# 验证 CSI Driver Pod 状态
kubectl get pods -n kube-system | grep secrets-store

# 验证 Vault CSI Provider Pod 状态
kubectl get pods -n kube-system | grep vault-csi-provider
```

### 5. 应用 SecretProviderClass

安装完成后，应用 cloudflare-vault-provider SecretProviderClass：

```bash
kubectl apply -f ./vault-sidecar-injector.yaml
```

## 快速安装脚本

为了快速解决 "secrets-store.csi.x-k8s.io/SecretProviderClass not found" 错误，您可以使用我们提供的自动化安装脚本：

```bash
# 添加执行权限
chmod +x install-vault-crd.sh

# 执行脚本
./install-vault-crd.sh
```

脚本会自动安装所有必要组件，并使用本地 YAML 文件避免网络连接问题。

## 注意事项

- 请确保 `kubectl` 命令可用并且已配置正确的集群上下文
- 安装过程中需要集群管理员权限
- 安装完成后，需要等待所有 Pod 状态变为 Running
- 安装后需要重新部署应用以确保正确加载 SecretProviderClass

## 故障排除

如果安装后仍然遇到问题：

1. 确认所有组件都已正确安装：
   ```bash
   kubectl get crd | grep secret
   kubectl get pods -n kube-system | grep -E "secrets-store|vault-csi"
   ```

2. 检查 SecretProviderClass 是否已创建：
   ```bash
   kubectl get secretproviderclass -A
   ```

3. 查看相关 Pod 的日志以获取更多信息

4. 参考 Vault 官方文档：https://www.vaultproject.io/docs/platform/k8s/csi