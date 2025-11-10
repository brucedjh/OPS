Write-Host "=== Vault脚本环境测试 ===" -ForegroundColor Cyan

# 检测必要工具
Write-Host "
检查必要工具..."
$curlExists = Get-Command curl -ErrorAction SilentlyContinue
$kubectlExists = Get-Command kubectl -ErrorAction SilentlyContinue

if (-not $curlExists) {
    Write-Host "❌ 错误: curl命令未找到，请安装curl或确保它在PATH中" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ curl 已安装: $($curlExists.Source)" -ForegroundColor Green
}

if (-not $kubectlExists) {
    Write-Host "❌ 错误: kubectl命令未找到，请安装kubectl或确保它在PATH中" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ kubectl 已安装: $($kubectlExists.Source)"
}

# 检查Vault地址
Write-Host "
检查Vault服务器连接..."
$vaultAddr = "http://192.168.2.50:8200"
try {
    $response = Invoke-WebRequest -Uri "$vaultAddr/v1/sys/health" -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200 -or ($response.StatusCode -ge 472 -and $response.StatusCode -le 475)) {
        Write-Host "✅ Vault服务器可达: $vaultAddr" -ForegroundColor Green
        
        # 检查Vault密封状态
        $content = $response.Content | ConvertFrom-Json
        if ($content.sealed -eq $true) {
            Write-Host "❌ Vault已密封，请先解封Vault" -ForegroundColor Red
            Write-Host "请访问 $vaultAddr 进行解封操作"
        } else {
            Write-Host "✅ Vault状态正常，未密封" -ForegroundColor Green
        }
    } else {
        Write-Host "❌ 无法连接到Vault服务器: $vaultAddr" -ForegroundColor Red
        Write-Host "HTTP状态码: $($response.StatusCode)"
    }
} catch {
    Write-Host "❌ 连接Vault服务器失败: $_" -ForegroundColor Red
}

# 检查Kubernetes连接
Write-Host "
检查Kubernetes连接..."
try {
    $context = kubectl config current-context
    if ($context) {
        Write-Host "✅ Kubernetes配置正常: 当前上下文为 '$context'" -ForegroundColor Green
        
        # 检查服务账户
        Write-Host "
检查服务账户 'cloudflare-app-example-app'..."
        $saCheck = kubectl get sa cloudflare-app-example-app -n default -o json 2>$null
        if ($saCheck) {
            Write-Host "✅ 服务账户 'cloudflare-app-example-app' 已存在" -ForegroundColor Green
        } else {
            Write-Host "⚠️  服务账户 'cloudflare-app-example-app' 不存在，运行前请先执行 ./deploy-local.sh" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "❌ Kubernetes连接失败: $_" -ForegroundColor Red
}

# 显示使用说明
Write-Host "
=== 使用说明 ===" -ForegroundColor Cyan
Write-Host "1. 确保Vault服务器已启动且未密封"
Write-Host "2. 确保Kubernetes服务账户已创建: ./deploy-local.sh"
Write-Host "3. 在Linux/Mac环境中运行配置脚本: ./configure-vault-k8s.sh"
Write-Host "4. 按提示输入有效的Vault根令牌"

Write-Host "
环境测试完成!" -ForegroundColor Green