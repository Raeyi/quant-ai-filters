# Self-Hosted Runner 设置指南

本文档说明如何在本地机器上配置 GitHub Actions Self-Hosted Runner。

## 为什么使用 Self-Hosted Runner？

| 特性 | GitHub-Hosted | Self-Hosted |
|------|---------------|-------------|
| MT5 环境 | 需要每次下载 | ✅ 已安装 |
| 编译速度 | 慢（需下载） | ✅ 快 |
| 机器状态 | 临时 | ✅ 持久 |
| 费用 | 免费额度有限 | ✅ 免费 |
| 适用场景 | 临时测试 | ✅ 正式构建 |

## 前置条件

- Windows 10/11 或 Windows Server
- MT5 已安装（需确认 MetaEditor 路径）
- 网络可访问 GitHub

## 设置步骤

### 1. 获取 Runner Token

1. 打开 GitHub 仓库
2. Settings → Actions → Runners
3. 点击 "New self-hosted runner"
4. 选择 "Windows"
5. 记录下 Token（只需一次）

### 2. 下载并配置 Runner

```powershell
# 创建 Runner 目录
mkdir C:\actions-runner
cd C:\actions-runner

# 下载 Runner（使用 GitHub 提供的链接）
Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-win-x64-2.321.0.zip -OutFile actions-runner-win-x64-2.321.0.zip

# 解压
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PWD/actions-runner-win-x64-2.321.0.zip", "$PWD")

# 配置（替换 YOUR_TOKEN）
./config.cmd --url https://github.com/Raeyi/quant-ai-filters --token YOUR_TOKEN --labels self-hosted-windows

# 设置为 Windows 服务（推荐）
./svc.sh install
./svc.sh start
```

### 3. 验证 MT5 路径

```powershell
# 检查 MetaEditor 是否存在
$editor = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
if (Test-Path $editor) {
    Write-Host "MetaEditor found: $editor"
} else {
    Write-Host "MetaEditor not found, checking alternatives..."
    Get-ChildItem "C:\Program Files*\MetaTrader 5" -Recurse -Filter "MetaEditor64.exe" -ErrorAction SilentlyContinue
}
```

### 4. 测试 Workflow

1. 推送代码到 `EA_2.*` 分支
2. 或手动触发：Actions → Build EA (Self-Hosted) → Run workflow

## 离线 MT5 安装方案

如果使用离线安装包 `E:\ChromeDownload\mt5setup.exe`：

```powershell
# 方案 1: 安装到默认路径
Start-Process "E:\ChromeDownload\mt5setup.exe" -ArgumentList "/S" -Wait

# 方案 2: 便携版安装（推荐 CI/CD）
$mt5Path = "C:\MT5"
mkdir $mt5Path
# 手动解压或安装到该目录

# 验证安装
Get-ChildItem "C:\MT5" -Recurse -Filter "*.exe" | Select-Object Name, FullName
```

## Runner 维护

### 查看状态
```powershell
cd C:\actions-runner
./svc.sh status
```

### 重启服务
```powershell
cd C:\actions-runner
./svc.sh stop
./svc.sh start
```

### 更新 Runner
```powershell
cd C:\actions-runner
./svc.sh stop
./run.cmd --once  # 运行一次以获取更新
./svc.sh start
```

### 查看日志
```powershell
Get-Content C:\actions-runner\_diag\Runner_*.log -Tail 100
```

## 安全建议

1. **Runner 用户**: 创建专用 Windows 用户运行 Runner
2. **权限**: 仅授予必要权限
3. **网络**: 确保出站 HTTPS (443) 端口开放
4. **监控**: 定期检查 Runner 日志

## 故障排除

### Runner 离线
1. 检查服务状态: `./svc.sh status`
2. 检查网络连接
3. 查看 Runner 日志

### 编译失败
1. 确认 MetaEditor 路径正确
2. 检查 .mq5 文件编码（UTF-8）
3. 查看 compile.log

### 权限错误
1. 确保 Runner 用户有 MT5 目录访问权限
2. 确保 Runner 用户有工作目录写入权限
