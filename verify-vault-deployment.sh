#!/bin/bash

# 确保脚本在Linux环境下有正确的执行权限
# 请在Linux系统上运行以下命令为脚本添加执行权限：
# chmod +x verify-vault-deployment.sh

# 验证Vault和SecretProviderClass部署状态的脚本
echo "开始验证Vault和SecretProviderClass部署状态..."

# 1. 检查CSIDriver是否已安装
echo "\n1. 检查CSIDriver..."
if kubectl get csidriver | grep -q "secrets-store.csi.k8s.io"; then
  echo "✅ CSIDriver 已安装"
  kubectl get csidriver secrets-store.csi.k8s.io
else
  echo "❌ CSIDriver 未安装，请先运行 install-vault-crd.sh"
fi

# 2. 检查SecretProviderClass CRD是否已安装
echo "\n2. 检查SecretProviderClass CRD..."
if kubectl get crd | grep -q "secretproviderclasses"; then
  echo "✅ SecretProviderClass CRD 已安装"
  kubectl get crd secretproviderclasses.secrets-store.csi.x-k8s.io
else
  echo "❌ SecretProviderClass CRD 未安装，请先运行 install-vault-crd.sh"
fi

# 3. 检查SecretProviderClassPodStatus CRD是否已安装
echo "\n3. 检查SecretProviderClassPodStatus CRD..."
if kubectl get crd | grep -q "secretproviderclasspodstatuses"; then
  echo "✅ SecretProviderClassPodStatus CRD 已安装"
  kubectl get crd secretproviderclasspodstatuses.secrets-store.csi.x-k8s.io
else
  echo "❌ SecretProviderClassPodStatus CRD 未安装，请先运行 install-vault-crd.sh"
fi

# 4. 检查CSI驱动程序Pod状态
echo "\n4. 检查CSI驱动程序Pod..."
if kubectl get pods -n kube-system | grep -q "secrets-store-csi-driver"; then
  echo "✅ Secrets Store CSI Driver Pod 存在"
  kubectl get pods -n kube-system | grep secrets-store-csi-driver
else
  echo "❌ Secrets Store CSI Driver Pod 不存在"
fi

# 5. 检查Vault CSI Provider Pod状态
echo "\n5. 检查Vault CSI Provider Pod..."
if kubectl get pods -n kube-system | grep -q "vault-csi-provider"; then
  echo "✅ Vault CSI Provider Pod 存在"
  kubectl get pods -n kube-system | grep vault-csi-provider
else
  echo "❌ Vault CSI Provider Pod 不存在"
fi

# 6. 检查cloudflare-vault-provider SecretProviderClass
echo "\n6. 检查cloudflare-vault-provider SecretProviderClass..."
if kubectl get secretproviderclass -A | grep -q "cloudflare-vault-provider"; then
  echo "✅ cloudflare-vault-provider SecretProviderClass 已创建"
  kubectl get secretproviderclass cloudflare-vault-provider -o yaml
else
  echo "❌ cloudflare-vault-provider SecretProviderClass 未创建"
  echo "请运行: kubectl apply -f ./vault-sidecar-injector.yaml"
fi

# 7. 检查应用Pod状态
echo "\n7. 检查应用Pod状态..."
if kubectl get pods -l app=example-app 2>/dev/null; then
  POD_NAME=$(kubectl get pods -l app=example-app -o jsonpath="{.items[0].metadata.name}")
  echo "\n8. 检查应用Pod中的Vault集成..."
  
  # 检查凭证目录是否存在
  if kubectl exec $POD_NAME -- ls -la /apps/credential 2>/dev/null; then
    echo "✅ 凭证目录 /apps/credential 存在"
    
    # 检查凭证文件是否存在
    if kubectl exec $POD_NAME -- ls -la /apps/credential/cloudflare_email.txt 2>/dev/null; then
      echo "✅ 凭证文件 cloudflare_email.txt 存在"
    else
      echo "❌ 凭证文件 cloudflare_email.txt 不存在"
    fi
    
    if kubectl exec $POD_NAME -- ls -la /apps/credential/cloudflare_api_key.txt 2>/dev/null; then
      echo "✅ 凭证文件 cloudflare_api_key.txt 存在"
    else
      echo "❌ 凭证文件 cloudflare_api_key.txt 不存在"
    fi
  else
    echo "❌ 凭证目录 /apps/credential 不存在"
  fi
  
  # 检查应用日志中的Vault相关信息
  echo "\n7. 检查应用日志中的Vault信息..."
  kubectl logs $POD_NAME | grep -i vault
else
  echo "⚠️  未找到应用Pod，请先部署应用"
fi

echo "\n验证完成！"
echo "如果所有检查都通过，Vault CSI集成应该正常工作。"
echo "如果有任何失败，请参考 OPS/INSTALL-VAULT-CSI-GUIDE.md 进行故障排除。"