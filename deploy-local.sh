#!/bin/bash

# 本地K8S环境部署脚本

set -e

# 配置参数
APP_NAME="example-app"
NAMESPACE="example-namespace"
LOCAL_PORT="8080"
SERVICE_PORT="80"

# 创建命名空间
echo "创建命名空间..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 检查镜像拉取密钥
echo "检查镜像拉取密钥..."
if ! kubectl get secret aliyun-acr-credentials -n "${NAMESPACE}" &> /dev/null; then
    echo "警告: 镜像拉取密钥 'aliyun-acr-credentials' 不存在，请确保已正确创建"
    echo "使用以下命令创建密钥："
    echo "kubectl create secret docker-registry aliyun-acr-credentials \\
  --docker-server=registry.cn-hangzhou.aliyuncs.com \\
  --docker-username=你的用户名 \\
  --docker-password=你的密码 \\
  --docker-email=your-email@example.com \\
  -n ${NAMESPACE}"
    # 暂停等待用户输入
    read -p "按回车键继续部署（不使用密钥）或按Ctrl+C取消..."
fi

# 部署应用
echo "部署应用..."
helm upgrade --install "${APP_NAME}" ./charts/example-app \
  --namespace "${NAMESPACE}" \
  --set image.tag=latest \
  --wait

# 等待Pod就绪
echo "等待Pod就绪..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name="${APP_NAME}" -n "${NAMESPACE}" --timeout=300s

# 显示部署状态
echo "\n部署状态："
kubectl get pods -n "${NAMESPACE}"
kubectl get svc -n "${NAMESPACE}"

# 启动port-forward
echo "\n启动Port-Forward (${LOCAL_PORT}:${SERVICE_PORT})..."
echo "访问地址: http://localhost:${LOCAL_PORT}"
echo "按 Ctrl+C 停止转发"
echo "\n"
kubectl port-forward svc/"${APP_NAME}" -n "${NAMESPACE}" "${LOCAL_PORT}:${SERVICE_PORT}"