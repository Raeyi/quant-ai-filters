# MT5 回测数据快速分析脚本 (v2.4.0+)
# 用法: .\analyze_backtest.ps1 -SignalsFile "C:\path\to\signals_mt5.csv"
#       .\analyze_backtest.ps1 -SignalsFile "signals.csv" -FeaturesFile "features.csv"

param(
    [Parameter(Mandatory=$true)]
    [string]$SignalsFile,
    
    [Parameter(Mandatory=$false)]
    [string]$FeaturesFile
)

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "MT5 回测数据快速分析 (v2.4.0+)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# 检查文件
if (-not (Test-Path $SignalsFile)) {
    Write-Host "错误: 文件不存在 - $SignalsFile" -ForegroundColor Red
    exit 1
}

# 加载数据
$data = Import-Csv $SignalsFile -Delimiter "`t"
$total = $data.Count

Write-Host ""
Write-Host "数据概览:" -ForegroundColor Yellow
Write-Host "  总记录数: $total"

# 1. Regime 状态分布
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "1. Regime 状态分布" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

$regimeStates = $data | ForEach-Object { 
    if ($_.regime) { $_.regime.Split('|')[0] } 
} | Group-Object | Sort-Object Count -Descending

foreach ($state in $regimeStates) {
    $pct = [math]::Round($state.Count / $total * 100, 1)
    $bar = "█" * [math]::Floor($pct / 5)
    Write-Host "  $($state.Name): $($state.Count) ($pct%) $bar"
}

# 2. SubType 分布
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "2. SubType 分布" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

$subtypes = $data | ForEach-Object { 
    if ($_.regime -and $_.regime.Split('|').Count -gt 1) { $_.regime.Split('|')[1] } 
} | Group-Object | Sort-Object Count -Descending

$subtypeNames = @{
    'T+V-B' = '真趋势'
    'T+V-A' = '情绪脉冲'
    'T+N'   = '温和趋势'
    'R+V-B' = '假突破密集'
    'R+V-A' = '消息震荡'
    'R+N'   = '正常震荡'
    'R+L'   = '低波动震荡'
}

foreach ($subtype in $subtypes) {
    $name = $subtypeNames[$subtype.Name]
    $pct = [math]::Round($subtype.Count / $total * 100, 1)
    Write-Host "  $($subtype.Name) ($name): $($subtype.Count) ($pct%)"
}

# 3. 入场条件检查 (关键!)
Write-Host ""
Write-Host "============================================" -ForegroundColor Red
Write-Host "3. 入场条件检查 (关键)" -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Red

$entries = $data | Where-Object { $_.source -and $_.source -ne '' }
$entryCount = $entries.Count

if ($entryCount -eq 0) {
    Write-Host "  未找到入场信号!" -ForegroundColor Yellow
} else {
    Write-Host "  入场信号总数: $entryCount" -ForegroundColor Yellow
    
    # 入场时的 Regime 状态
    Write-Host ""
    Write-Host "  入场时的 Regime 状态:" -ForegroundColor Yellow
    $entryStates = $entries | ForEach-Object { 
        if ($_.regime) { $_.regime.Split('|')[0] } 
    } | Group-Object | Sort-Object Count -Descending
    
    $standbyCount = 0
    foreach ($state in $entryStates) {
        $pct = [math]::Round($state.Count / $entryCount * 100, 1)
        $warning = if ($state.Name -eq 'STANDBY' -and $pct -gt 10) { " ⚠️ 问题!" } else { "" }
        Write-Host "    $($state.Name): $($state.Count) ($pct%)$warning"
        if ($state.Name -eq 'STANDBY') { $standbyCount = $state.Count }
    }
    
    $standbyPct = [math]::Round($standbyCount / $entryCount * 100, 1)
    if ($standbyPct -gt 5) {
        Write-Host ""
        Write-Host "  ❌ 严重问题: $standbyPct% 的入场发生在 STANDBY 状态!" -ForegroundColor Red
    }
}

# 4. 入场时间分布
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "4. 入场时间分布" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

if ($entryCount -gt 0) {
    $entryHours = $entries | ForEach-Object { 
        [int]$_.time.Split(' ')[1].Split(':')[0]
    } | Group-Object | Sort-Object Name
    
    $lowLiquidityCount = 0
    Write-Host "  小时分布:"
    foreach ($hour in $entryHours) {
        $h = [int]$hour.Name
        $session = if ($h -ge 0 -and $h -lt 6) { "低流动性" }
                   elseif ($h -ge 16 -and $h -lt 20) { "欧洲" }
                   elseif ($h -ge 20 -and $h -lt 24) { "欧美重叠" }
                   else { "其他" }
        $warning = if ($session -eq "低流动性") { " ⚠️" } else { "" }
        Write-Host "    $($hour.Name):00 - $($hour.Count) 次 ($session)$warning"
        if ($session -eq "低流动性") { $lowLiquidityCount += $hour.Count }
    }
    
    $lowLiquidityPct = [math]::Round($lowLiquidityCount / $entryCount * 100, 1)
    if ($lowLiquidityPct -gt 0) {
        Write-Host ""
        Write-Host "  ❌ 低流动性时段入场: $lowLiquidityCount 次 ($lowLiquidityPct%)" -ForegroundColor Red
    }
}

# 5. Q-Score 分布
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "5. Q-Score 分布" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

$qScores = $data | ForEach-Object { 
    if ($_.regime -and $_.regime.Split('|').Count -gt 2) { 
        [double]$_.regime.Split('|')[2].Replace('Q', '')
    } 
} | Where-Object { $_ -gt 0 }

if ($qScores) {
    $qArray = $qScores | ForEach-Object { $_ }
    $mean = [math]::Round(($qArray | Measure-Object -Average).Average, 3)
    $min = [math]::Round(($qArray | Measure-Object -Minimum).Minimum, 3)
    $max = [math]::Round(($qArray | Measure-Object -Maximum).Maximum, 3)
    
    Write-Host "  均值: $mean"
    Write-Host "  最小: $min"
    Write-Host "  最大: $max"
}

# 6. 信号来源
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "6. 信号来源" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

if ($entryCount -gt 0) {
    $sources = $entries | Group-Object source | Sort-Object Count -Descending
    foreach ($src in $sources) {
        $shortName = $src.Name.Replace('combo_single_', '')
        Write-Host "  $shortName : $($src.Count)"
    }
}

# 7. 扩展特征分析 (如果提供了特征文件)
if ($FeaturesFile -and (Test-Path $FeaturesFile)) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "7. 扩展特征分析" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    
    $features = Import-Csv $FeaturesFile -Delimiter "`t"
    $featureCount = $features.Count
    
    # 检查列数
    $cols = $features[0].PSObject.Properties.Name
    Write-Host "  特征记录数: $featureCount"
    Write-Host "  特征列数: $($cols.Count)"
    
    if ($cols.Count -lt 15) {
        Write-Host "  ⚠️ 特征列数不足，建议重新运行 EA 生成完整数据" -ForegroundColor Yellow
    } else {
        Write-Host "  ✅ 特征数据完整，可用于 ML/RL 训练" -ForegroundColor Green
    }
    
    # 显示部分特征统计
    if ($features[0].q_score) {
        $qScoreVals = $features | ForEach-Object { [double]$_.q_score } | Where-Object { $_ -gt 0 }
        if ($qScoreVals) {
            $qMean = [math]::Round(($qScoreVals | Measure-Object -Average).Average, 3)
            Write-Host "  Q-Score 均值: $qMean"
        }
    }
}

# 诊断报告
Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "诊断报告" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

$issues = @()

if ($entryCount -gt 0 -and $standbyPct -gt 5) {
    $issues += "STANDBY 状态入场比例过高 ($standbyPct%)"
}

if ($entryCount -gt 0 -and $lowLiquidityPct -gt 0) {
    $issues += "低流动性时段有入场 ($lowLiquidityPct%)"
}

if ($issues.Count -eq 0) {
    Write-Host "✅ 数据正常，可以进行优化" -ForegroundColor Green
} else {
    Write-Host "发现以下问题:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  ❌ $issue" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "分析完成" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
