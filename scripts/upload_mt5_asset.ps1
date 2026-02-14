# =============================================================================
# 上传 MT5 安装包到 GitHub Release
# =============================================================================
# 用法: .\scripts\upload_mt5_asset.ps1 -InstallerPath "E:\ChromeDownload\mt5setup.exe"
# 前置条件: 已安装 GitHub CLI (gh) 并登录
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallerPath
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Upload MT5 Installer to GitHub" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 检查文件
if (-not (Test-Path $InstallerPath)) {
    Write-Host "ERROR: File not found: $InstallerPath" -ForegroundColor Red
    exit 1
}

$fileInfo = Get-Item $InstallerPath
Write-Host ""
Write-Host "File: $($fileInfo.FullName)"
Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB"

# 检查 gh CLI
Write-Host ""
Write-Host "Checking GitHub CLI..." -ForegroundColor Yellow

$ghVersion = gh --version 2>$null
if (-not $ghVersion) {
    Write-Host "ERROR: GitHub CLI not installed!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Install from: https://cli.github.com/"
    Write-Host "Or run: winget install GitHub.cli"
    exit 1
}

Write-Host "  $ghVersion" -ForegroundColor Gray

# 检查登录状态
Write-Host ""
Write-Host "Checking GitHub login status..." -ForegroundColor Yellow

$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Not logged in to GitHub!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run: gh auth login"
    exit 1
}

Write-Host "  Logged in" -ForegroundColor Green

# 获取仓库信息
$repo = gh repo view --json nameWithOwner -q .nameWithOwner
Write-Host ""
Write-Host "Repository: $repo" -ForegroundColor Cyan

# 创建/更新 Release
$releaseTag = "mt5-assets"
$releaseName = "MT5 Assets"

Write-Host ""
Write-Host "Checking release '$releaseTag'..." -ForegroundColor Yellow

$existingRelease = gh release view $releaseTag 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Release exists, will update" -ForegroundColor Green
} else {
    Write-Host "  Creating new release..." -ForegroundColor Yellow
    gh release create $releaseTag --title $releaseName --notes "MT5 installation assets for CI/CD builds"
}

# 上传文件
Write-Host ""
Write-Host "Uploading MT5 installer..." -ForegroundColor Yellow

gh release upload $releaseTag $InstallerPath --clobber

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Upload completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Release URL: https://github.com/$repo/releases/tag/$releaseTag"
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  Upload failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    exit 1
}
