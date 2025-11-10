# 最简单的Vault连接测试

Write-Host "===== Vault连接测试 ====="

# 配置Vault地址
$VAULT_ADDR = "http://192.168.2.50:8200"

Write-Host "测试Vault服务器: $VAULT_ADDR"

# 使用简单方法测试连接
$ErrorActionPreference = 'Stop'

try {
    $response = Invoke-RestMethod -Uri "$VAULT_ADDR/v1/sys/health"
    Write-Host "\n成功连接到Vault!"
    Write-Host "初始化状态: $($response.initialized)"
    Write-Host "密封状态: $($response.sealed)"
    Write-Host "Vault版本: $($response.version)"
} catch {
    Write-Host "\n连接失败!"
    Write-Host "错误: $_.Exception.Message"
}

Write-Host "\n测试完成"