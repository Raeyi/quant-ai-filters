# 版本管理指南

## 版本号规则（语义化版本）

```
MAJOR.MINOR.PATCH (如 2.1.0)

- MAJOR: 重大架构变更（如 2.x → 3.x）
- MINOR: 里程碑完成（M1=1, M2=2, M3=3）
- PATCH: Bug修复/小优化
```

## 版本更新流程

### 方式一：自动（推荐）

里程碑完成后合并到 `EA_2.0.0` 分支，CI/CD 自动：
1. 更新 `Core/Version.mqh` 版本号
2. 编译 `Ea_run.ex5`
3. 创建 GitHub Release
4. 上传编译产物

### 方式二：手动

1. 更新 `Core/Version.mqh`：
```mqh
#define EA_VERSION_MAJOR    2
#define EA_VERSION_MINOR    1    // M1 完成
#define EA_VERSION_PATCH    0
#define EA_VERSION_STRING   "2.1.0"
```

2. 提交并打 tag：
```bash
git add Core/Version.mqh
git commit -m "chore: bump version to 2.1.0"
git tag v2.1.0
git push origin EA_2.0.0 --tags
```

## 版本历史

| 版本 | 里程碑 | 日期 | 说明 |
|------|--------|------|------|
| 2.0.0 | - | - | 初始版本 |
| 2.1.0 | M1 | - | Mean Reversion Family 完成 |
| 2.2.0 | M2 | - | Trend Pullback Family 完成 |
| 2.3.0 | M3 | - | XAUUSD Alpha 完成 |

## CI/CD 配置

### Self-Hosted Runner 设置

在本地机器（有 MT5 环境）上运行：

```powershell
# 1. 下载 GitHub Actions Runner
# https://github.com/{owner}/{repo}/settings/actions/runners/new

# 2. 解压并配置
./config.cmd --url https://github.com/{owner}/{repo} --token {TOKEN}

# 3. 设置标签为 "self-hosted-windows"
# 4. 运行 runner
./run.cmd
```

### 环境变量

在 GitHub 仓库设置中配置：
- `MT5_PATH`: MT5 安装路径（默认 `C:\Program Files\MetaTrader 5`）

## 分支策略

```
EA_2.0.0 (主分支，受保护)
    ↑
    ├── milestone/m1-mean-reversion-family → 合并 → v2.1.0
    ├── milestone/m2-trend-pullback       → 合并 → v2.2.0
    └── milestone/m3-xauusd-alpha         → 合并 → v2.3.0
```

### 合并规则

1. 里程碑开发在 `milestone/m*` 分支
2. 完成后创建 PR 合并到 `EA_2.0.0`
3. PR 合并后自动触发 CI/CD
4. 版本号自动更新

## 手动触发构建

在 GitHub Actions 页面：
1. 选择 "Build EA & Release" workflow
2. 点击 "Run workflow"
3. 选择版本号升级类型（major/minor/patch）
4. 执行
