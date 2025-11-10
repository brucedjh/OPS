# 简单的Vault连接测试脚本 - PowerShell版本

Write-Host "===== Vault连接测试 =====" -ForegroundColor Cyan

# 配置Vault地址
$VAULT_ADDR = "http://192.168.2.50:8200"

Write-Host "测试Vault服务器: $VAULT_ADDR"

# 简单测试Vault健康状态
Write-Host "\n检查Vault服务器状态..."

try {
    $response = Invoke-RestMethod -Uri "$VAULT_ADDR/v1/sys/health" -ErrorAction Stop
    
    Write-Host "✅ 成功连接到Vault服务器" -ForegroundColor Green
    Write-Host "初始化状态: $($response.initialized)" -ForegroundColor Green
    Write-Host "密封状态: $($response.sealed)" -ForegroundColor Green
    Write-Host "Vault版本: $($response.version)" -ForegroundColor Green
    
    if ($response.sealed -eq $false) {
        Write-Host "\n✅ Vault未密封，可以进行操作" -ForegroundColor Green
    } else {
        Write-Host "\n❌ Vault已密封，请先解封" -ForegroundColor Red
    }
} catch {
    Write-Host "\n❌ 连接Vault服务器失败" -ForegroundColor Red
    Write-Host "错误信息: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "\n===== 测试完成 =====" -ForegroundColor Cyan