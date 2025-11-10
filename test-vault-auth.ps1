# 简单的PowerShell脚本测试Vault认证

Write-Host "===== Vault认证测试 - PowerShell版本 =====" -ForegroundColor Cyan

# 配置参数
$VAULT_ADDR = "http://192.168.2.50:8200"
$VAULT_K8S_ROLE = "cloudflare-app-role"
$APP_NAME = "cloudflare-app-example-app"
$NAMESPACE = "default"

Write-Host "\n配置信息:"
Write-Host "Vault地址: $VAULT_ADDR"
Write-Host "Vault角色: $VAULT_K8S_ROLE"
Write-Host "应用名称: $APP_NAME"
Write-Host "命名空间: $NAMESPACE"

# 检查Vault服务器状态
Write-Host "\n检查Vault服务器状态..." -ForegroundColor Yellow
try {
    $healthResponse = Invoke-RestMethod -Uri "$VAULT_ADDR/v1/sys/health" -ErrorAction Stop
    Write-Host "✅ Vault服务器可达" -ForegroundColor Green
    
    if ($healthResponse.sealed -eq $false) {
        Write-Host "✅ Vault未密封" -ForegroundColor Green
    } else {
        Write-Host "❌ Vault已密封，请先解封Vault" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Vault版本: $($healthResponse.version)"
    Write-Host "初始化状态: $($healthResponse.initialized)"
} catch {
    Write-Host "❌ 无法连接到Vault服务器" -ForegroundColor Red
    Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 检查环境变量中的VAULT_TOKEN
Write-Host "\n检查VAULT_TOKEN环境变量..." -ForegroundColor Yellow
$vaultToken = $env:VAULT_TOKEN

if (-not [string]::IsNullOrEmpty($vaultToken)) {
    Write-Host "✅ 检测到VAULT_TOKEN环境变量" -ForegroundColor Green
    Write-Host "Token长度: $($vaultToken.Length)"
    
    # 测试token认证
    Write-Host "\n测试token认证..." -ForegroundColor Yellow
    try {
        $headers = @{"Authorization" = "Bearer $vaultToken"}
        $tokenResponse = Invoke-RestMethod -Uri "$VAULT_ADDR/v1/auth/token/lookup-self" -Headers $headers -ErrorAction Stop
        Write-Host "✅ Token认证成功!" -ForegroundColor Green
        
        # 测试读取Secret
        Write-Host "\n测试读取Vault密钥..." -ForegroundColor Yellow
        try {
            $secretResponse = Invoke-RestMethod -Uri "$VAULT_ADDR/v1/secret/data/cloudflare" -Headers $headers -ErrorAction Stop
            Write-Host "✅ 成功读取Vault密钥!" -ForegroundColor Green
            Write-Host "认证和授权配置正确"
        } catch {
            Write-Host "❌ 无法读取Vault密钥，可能权限不足" -ForegroundColor Red
            Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
            # 尝试获取详细错误
            try {
                $errorContent = $_.Exception.Response.GetResponseStream() | New-Object System.IO.StreamReader | ReadToEnd()
                Write-Host "错误详情: $errorContent" -ForegroundColor Red
                
                if ($errorContent -like "*permission denied*") {
                    Write-Host "提示: Vault返回权限被拒绝，请检查策略配置" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "无法获取详细错误信息" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "❌ Token认证失败" -ForegroundColor Red
        Write-Host "错误: $($_.Exception.Message)" -ForegroundColor Red
        # 尝试获取详细错误
        try {
            $errorContent = $_.Exception.Response.GetResponseStream() | New-Object System.IO.StreamReader | ReadToEnd()
            Write-Host "错误详情: $errorContent" -ForegroundColor Red
        } catch {
            Write-Host "无法获取详细错误信息" -ForegroundColor Red
        }
    }
} else {
    Write-Host "❌ 未检测到VAULT_TOKEN环境变量" -ForegroundColor Red
    Write-Host "\n请设置VAULT_TOKEN环境变量进行测试:"
    Write-Host " 示例: `$env:VAULT_TOKEN = 'your_vault_token_here'"
    
    Write-Host "\n故障排除建议:" -ForegroundColor Yellow
    Write-Host "1. 确保Vault服务器运行正常且未密封"
    Write-Host "2. 验证VAULT_ADDR是否正确指向您的Vault服务器"
    Write-Host "3. 检查您是否有正确的Vault管理员权限"
    Write-Host "4. 确认已在Vault中创建了所需的策略和路径"
}

Write-Host "\n===== 测试完成 =====" -ForegroundColor Cyan