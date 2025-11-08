# K8s集群前期准备与ArgoCD集成指南

本文档详细介绍如何为ArgoCD准备Kubernetes集群，包括集群添加、权限配置和最佳实践。

## 1. 前期准备工作

### 1.1 确保Kubernetes集群正常运行

```bash
# 检查集群健康状态
kubectl cluster-info

# 验证节点状态
kubectl get nodes

# 确认集群版本
kubectl version
```

### 1.2 配置kubectl访问权限

确保你有集群的管理员访问权限(kubeconfig文件)，这对于后续操作至关重要。

```bash
# 查看当前kubeconfig位置
kubectl config view

# 或者指定kubeconfig文件
export KUBECONFIG=/path/to/your/kubeconfig.yaml
```

## 2. ArgoCD安装(如果尚未安装)

如果ArgoCD还未安装，请参考以下步骤：

```bash
# 创建ArgoCD命名空间
kubectl create namespace argocd

# 安装ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 等待ArgoCD Pod就绪
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# 暴露ArgoCD UI(可选)
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## 3. 为ArgoCD创建集群访问凭证

### 3.1 创建服务账户和RBAC配置

创建一个名为`argocd-manager`的服务账户，并授予适当的权限：

```bash
# 创建服务账户
kubectl create serviceaccount argocd-manager -n kube-system

# 创建集群角色绑定
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin  # 在生产环境中，建议创建更严格的角色
subjects:
- kind: ServiceAccount
  name: argocd-manager
  namespace: kube-system
EOF
```

### 3.2 获取服务账户令牌

```bash
# 获取服务账户令牌
SECRET_NAME=$(kubectl get serviceaccount argocd-manager -n kube-system -o jsonpath='{.secrets[0].name}')
TOKEN=$(kubectl get secret $SECRET_NAME -n kube-system -o jsonpath='{.data.token}' | base64 --decode)
```

### 3.3 获取集群CA证书

```bash
# 获取集群CA证书
CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# 或者直接从secret获取
CA_CERT=$(kubectl get secret $SECRET_NAME -n kube-system -o jsonpath='{.data.ca\.crt}')
```

## 4. 将K8s集群添加到ArgoCD

### 4.1 使用ArgoCD CLI添加集群

首先安装ArgoCD CLI：

```bash
# 下载ArgoCD CLI (Linux/Mac)
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
mv argocd /usr/local/bin/

# 对于Windows，可以从GitHub Releases下载
```

然后登录并添加集群：

```bash
# 登录ArgoCD(假设ArgoCD UI在localhost:8080)
argocd login localhost:8080

# 获取集群服务器地址
SERVER=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')

# 添加集群到ArgoCD
argocd cluster add kube-system/argocd-manager --name my-k8s-cluster

# 或者使用令牌和CA证书手动添加
argocd cluster add --kubeconfig ~/.kube/config --name my-k8s-cluster
```

### 4.2 通过UI添加集群

1. 登录ArgoCD UI (https://localhost:8080)
2. 点击左侧菜单中的"Settings" -> "Clusters"
3. 点击"CONNECT CLUSTER"
4. 选择"Import Existing Kubeconfig"
5. 粘贴你的kubeconfig内容
6. 填写集群名称和命名空间
7. 点击"CONNECT"

## 5. 准备镜像仓库凭证

### 5.1 创建阿里云ACR访问凭证

为了能够拉取你的阿里云镜像，需要在集群中创建镜像拉取密钥：

```bash
# 创建镜像拉取密钥
kubectl create secret docker-registry aliyun-acr-credentials \
  --docker-server=crpi-dndp9yqzsi910o27.cn-hongkong.personal.cr.aliyuncs.com \
  --docker-username=你的ACR用户名 \
  --docker-password=你的ACR密码 \
  --docker-email=your-email@example.com \
  -n example-namespace
```

### 5.2 配置ArgoCD使用镜像凭证

```bash
# 创建命名空间(如果不存在)
kubectl create namespace example-namespace

# 将密钥复制到example-namespace(如果应用将部署到不同命名空间)
kubectl get secret aliyun-acr-credentials -n kube-system -o yaml | sed 's/namespace: kube-system/namespace: example-namespace/' | kubectl apply -f -
```

## 6. 验证准备工作

### 6.1 检查集群连接状态

```bash
# 使用ArgoCD CLI检查集群状态
argocd cluster list

# 检查服务账户权限
kubectl auth can-i --list --as=system:serviceaccount:kube-system:argocd-manager
```

### 6.2 预测试部署

```bash
# 使用kubectl创建一个测试Pod验证镜像拉取
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: example-namespace
spec:
  containers:
  - name: test-container
    image: crpi-dndp9yqzsi910o27.cn-hongkong.personal.cr.aliyuncs.com/ns_jadebruce/cloudflare:latest
    imagePullPolicy: Always
  imagePullSecrets:
  - name: aliyun-acr-credentials
EOF

# 检查Pod状态
kubectl get pod test-pod -n example-namespace

# 清理测试Pod
kubectl delete pod test-pod -n example-namespace
```

## 7. ArgoCD配置文件调整

现在你的K8s集群已准备就绪，需要更新`example-app-application.yaml`文件：

```bash
# 编辑Application配置文件
vi d:\code\OPS\argocd\example-app-application.yaml
```

主要调整以下内容：
1. `repoURL` - 设置为你的实际Git仓库地址
2. `destination.server` - 如果是外部集群，设置为正确的API服务器地址
3. `destination.namespace` - 确认为`example-namespace`

## 8. 应用ArgoCD配置

```bash
# 应用ArgoCD Application配置
kubectl apply -f d:\code\OPS\argocd\example-app-application.yaml

# 验证Application创建成功
kubectl get applications -n argocd
```

## 9. 监控部署状态

```bash
# 监控同步状态
argocd app get example-app

# 监控Pod状态
kubectl get pods -n example-namespace
```

## 10. 故障排除

### 常见问题

1. **集群连接失败**：检查服务账户权限和网络连接
2. **镜像拉取失败**：验证镜像拉取密钥和镜像地址
3. **同步失败**：检查Git仓库访问权限和网络连接

### 日志查看

```bash
# 查看ArgoCD服务器日志
kubectl logs deployment/argocd-server -n argocd

# 查看ArgoCD应用控制器日志
kubectl logs deployment/argocd-application-controller -n argocd
```

## 11. 最佳实践

1. **资源限制**：为ArgoCD组件设置适当的资源限制
2. **访问控制**：使用RBAC严格控制ArgoCD的访问权限
3. **监控**：配置Prometheus和Grafana监控ArgoCD和K8s集群
4. **备份**：定期备份ArgoCD配置和应用状态
5. **证书管理**：使用有效的TLS证书保护ArgoCD UI

---

完成以上步骤后，你的K8s集群就已经准备好通过ArgoCD进行GitOps部署了。