# K8S部署配置（Helm Chart + ArgoCD）

本项目使用Helm Chart管理Kubernetes部署配置，并通过ArgoCD实现GitOps自动化部署。

## 快速开始

### 新集群准备

如果你是刚开始设置Kubernetes集群并集成ArgoCD，请先参考：
- **[K8s集群前期准备与ArgoCD集成指南](k8s_argocd_setup_guide.md)** - 详细介绍如何准备K8s集群、安装ArgoCD、配置权限和添加集群等前期工作

## 项目结构

```
OPS/
├── charts/              # Helm Charts目录
│   └── example-app/      # 示例应用的Helm Chart
│       ├── Chart.yaml    # Chart元数据
│       ├── values.yaml   # 默认配置值
│       ├── charts/       # 子Chart目录
│       └── templates/    # Kubernetes清单模板
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── serviceaccount.yaml
│           └── autoscaling.yaml
├── argocd/              # ArgoCD配置
│   └── example-app-application.yaml  # ArgoCD Application定义
└── README.md           # 项目说明文档
```

## 使用说明

### 1. Helm Chart配置

#### 修改values.yaml

根据你的应用需求，修改 `charts/example-app/values.yaml` 文件：

- **镜像配置**：修改 `image.repository` 为你的阿里云ACR镜像地址
- **副本数**：调整 `replicaCount` 以满足你的服务需求
- **资源限制**：根据应用资源需求调整 `resources` 部分
- **服务配置**：默认已配置为 `ClusterIP` 类型，适合本地K8S环境使用port-forward访问

#### 镜像拉取密钥

确保在Kubernetes集群中创建了访问阿里云ACR的镜像拉取密钥：

```bash
kubectl create secret docker-registry aliyun-acr-credentials \
  --docker-server=registry.cn-hangzhou.aliyuncs.com \
  --docker-username=你的用户名 \
  --docker-password=你的密码 \
  --docker-email=your-email@example.com \
  -n example-namespace
```

### 2. 本地K8S环境使用说明

#### 使用Port-Forward访问应用

对于本地自建的Kubernetes环境，使用以下步骤通过port-forward访问应用：

1. **部署应用**：
   ```bash
   helm install example-app ./charts/example-app -n example-namespace --create-namespace
   ```

2. **使用port-forward访问**：
   ```bash
   # 将本地8080端口转发到服务的80端口
   kubectl port-forward svc/example-app -n example-namespace 8080:80
   ```

3. **访问应用**：
   打开浏览器，访问 `http://localhost:8080`

#### 查看部署状态

```bash
# 查看Pod状态
kubectl get pods -n example-namespace

# 查看服务状态
kubectl get svc -n example-namespace

# 查看Pod日志
kubectl logs -f deployment/example-app -n example-namespace
```

### 2. ArgoCD配置

#### 修改Application定义

编辑 `argocd/example-app-application.yaml` 文件：

- **仓库地址**：修改 `repoURL` 为你的GitHub仓库地址
- **命名空间**：修改 `destination.namespace` 为你希望部署应用的Kubernetes命名空间
- **参数配置**：根据需要调整其他参数

#### 应用ArgoCD配置

将Application配置应用到ArgoCD：

```bash
kubectl apply -f argocd/example-app-application.yaml
```

### 3. GitHub Actions集成

在你的应用代码仓库中，创建GitHub Actions工作流文件，用于构建镜像并更新部署配置：

```yaml
# .github/workflows/deploy.yaml
name: Build and Deploy

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v2
    
    - name: Login to Aliyun Container Registry
      uses: docker/login-action@v2
      with:
        registry: registry.cn-hangzhou.aliyuncs.com
        username: ${{ secrets.ALIYUN_ACR_USERNAME }}
        password: ${{ secrets.ALIYUN_ACR_PASSWORD }}
    
    - name: Build and push
      uses: docker/build-push-action@v4
      with:
        push: true
        tags: registry.cn-hangzhou.aliyuncs.com/your-namespace/your-app:${{ github.sha }}
    
    - name: Checkout OPS repository
      uses: actions/checkout@v3
      with:
        repository: your-org/your-ops-repo
        path: ops-repo
        token: ${{ secrets.GITHUB_TOKEN }}
    
    - name: Update image tag
      run: |
        cd ops-repo
        sed -i "s|image: \"registry.cn-hangzhou.aliyuncs.com/your-namespace/your-app:.*\"|image: \"registry.cn-hangzhou.aliyuncs.com/your-namespace/your-app:${{ github.sha }}\"|g" charts/example-app/values.yaml
        git config --global user.name 'GitHub Actions'
        git config --global user.email 'actions@github.com'
        git add charts/example-app/values.yaml
        git commit -m "Update image tag to ${{ github.sha }}"
        git push
```

## 最佳实践

1. **环境隔离**：为不同环境（开发、测试、生产）创建不同的values文件
   ```bash
   values-dev.yaml
   values-test.yaml
   values-prod.yaml
   ```

2. **密钥管理**：使用Kubernetes Secrets或外部密钥管理系统（如Vault）存储敏感信息

3. **资源监控**：配置资源限制和自动伸缩，确保应用性能和成本优化

4. **健康检查**：配置适当的存活和就绪探针，确保服务可用性

5. **GitOps工作流**：所有配置变更通过Git提交管理，利用ArgoCD自动同步到集群

## 故障排查

1. **镜像拉取失败**：检查镜像地址、标签和拉取密钥是否正确
2. **部署失败**：查看Pod事件和日志，确认资源是否足够、配置是否正确
3. **ArgoCD同步失败**：检查Git仓库权限、网络连接和配置格式

## 维护

- 定期更新Helm Chart和依赖版本
- 审查和优化资源配置
- 监控部署状态和应用性能