# Enhanced 参数扫描脚本
# 扫描参数: entry_mode, boll_period, boll_dev, ma_period, max_holding_bars

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PythonDir = Join-Path $ProjectRoot "Python"
$VenvPython = Join-Path $ProjectRoot "quant_venv\Scripts\python.exe"
$DataFile = "XAUUSD_M5_202509010100_202601302350.csv"
$OutputFile = Join-Path $ProjectRoot "data\param_sweep_enhanced_v2.csv"

Write-Host "=== Enhanced Parameter Sweep ===" -ForegroundColor Cyan
Write-Host "Data: $DataFile"
Write-Host "Output: $OutputFile"

Set-Location $PythonDir
$env:PYTHONPATH = $PythonDir

# 参数网格: 3 x 5 x 4 x 5 x 5 = 1500 组合
& $VenvPython "utils\param_sweep.py" `
    --config "config.json" `
    --source mt5 `
    --data $DataFile `
    --symbol XAUUSD `
    --timeframe M5 `
    --logic enhanced `
    --grid "entry_mode=A,B,C;boll_period=16,18,20,22,24;boll_dev=1.6,1.8,2.0,2.2;ma_period=40,50,60,70,80;max_holding_bars=5,8,10,12,15" `
    --top 30 `
    --sort ret_over_dd `
    --min-trades 50 `
    --max-dd 0.20 `
    --out "..\data\param_sweep_enhanced_v2.csv"

Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Results saved to: $OutputFile"
