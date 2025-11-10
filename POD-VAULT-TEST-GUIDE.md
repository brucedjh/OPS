# Pod内Vault认证测试指南

本文档介绍如何在Kubernetes Pod中使用`pod-vault-test.sh`脚本测试Vault认证和密钥访问权限。

## 前提条件

- 已配置好的Kubernetes集群
- 已部署的Vault服务器
- 已配置的Kubernetes服务账户（具有适当的RBAC权限）
- kubectl命令行工具（用于创建Pod和执行命令）

## 使用步骤

### 方法1：创建专用测试Pod

1. 首先，将`pod-vault-test.sh`脚本复制到本地：

   ```bash
   # 如果在本地开发机器上
   cd d:\code\cloudflare3\OPS
   ```

2. 创建一个临时Pod，挂载服务账户，并将测试脚本复制进去：

   ```bash
   # 创建测试Pod的YAML文件
   cat > test-pod.yaml <<EOF
   apiVersion: v1
   kind: Pod
   metadata:
     name: vault-auth-test-pod
     namespace: default
   spec:
     serviceAccountName: cloudflare-app-example-app  # 使用与应用相同的服务账户
     containers:
     - name: vault-test
       image: ubuntu:latest
       command: ["sleep", "3600"]
       volumeMounts:
       - name: test-script
         mountPath: /scripts
     volumes:
     - name: test-script
       emptyDir: {}
     restartPolicy: Never
   EOF

   # 应用Pod配置
   kubectl apply -f test-pod.yaml
   ```

3. 等待Pod启动：

   ```bash
   kubectl wait --for=condition=ready pod vault-auth-test-pod -n default --timeout=60s
   ```

4. 将测试脚本复制到Pod中：

   ```bash
   kubectl cp pod-vault-test.sh default/vault-auth-test-pod:/scripts/
   ```

5. 进入Pod并运行测试脚本：

   ```bash
   # 进入Pod
   kubectl exec -it vault-auth-test-pod -n default -- bash
   
   # 在Pod内执行
   cd /scripts
   chmod +x pod-vault-test.sh
   ./pod-vault-test.sh
   ```

### 方法2：使用现有的应用Pod（如果已部署）

如果您已经部署了使用相同服务账户的应用Pod，可以直接在该Pod中运行测试：

1. 首先，确认应用Pod的名称：

   ```bash
   kubectl get pods -n default -l app.kubernetes.io/name=example-app
   ```

2. 将测试脚本复制到应用Pod中：

   ```bash
   APP_POD_NAME=$(kubectl get pods -n default -l app.kubernetes.io/name=example-app -o jsonpath="{.items[0].metadata.name}")
   kubectl cp pod-vault-test.sh default/${APP_POD_NAME}:/tmp/
   ```

3. 在应用Pod中运行测试脚本：

   ```bash
   kubectl exec -it ${APP_POD_NAME} -n default -- bash -c "chmod +x /tmp/pod-vault-test.sh && /tmp/pod-vault-test.sh"
   ```

## 自定义配置

脚本支持通过环境变量进行自定义配置：

```bash
# 自定义Vault地址和角色
VAULT_ADDR="http://your-vault-server:8200" VAULT_K8S_ROLE="your-custom-role" ./pod-vault-test.sh
```

## 故障排除

### 常见错误及解决方法

1. **连接失败**
   - 检查Vault服务器地址是否正确
   - 验证网络策略是否允许Pod访问Vault服务
   - 确认Vault服务是否正在运行

2. **认证失败**
   - 检查Vault角色配置是否正确
   - 验证服务账户是否有权限使用此角色
   - 确认服务账户令牌是否有效

3. **权限被拒绝**
   - 检查Vault策略是否允许访问所需的密钥路径
   - 验证角色绑定是否正确
   - 确认密钥路径是否存在

## 清理

测试完成后，记得清理测试资源：

```bash
# 删除测试Pod
kubectl delete pod vault-auth-test-pod -n default

# 删除Pod配置文件
rm test-pod.yaml
```

## 成功标准

测试成功的标志：
1. Vault连接测试通过
2. Kubernetes认证测试通过
3. 至少能访问一个Cloudflare配置路径（默认路径或独立路径）

如果所有测试都通过，说明应用应该能够成功从Vault获取配置。