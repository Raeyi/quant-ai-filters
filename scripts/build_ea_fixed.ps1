# EA 鏈湴缂栬瘧鑴氭湰
# 鐢ㄦ硶: .\scripts\build_ea.ps1 [-MT5Path "C:\MT5"]

param(
    [string]$MT5Path = ""
)

$ErrorActionPreference = "Stop"

# 椤圭洰璺緞
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$SourceFile = Join-Path $ProjectRoot "Ea_run.mq5"
$OutputFile = Join-Path $ProjectRoot "Ea_run.ex5"

Write-Host "========================================"
Write-Host "  EA Build Script"
Write-Host "========================================"

# 鏌ユ壘 MetaEditor
Write-Host "Step 1: Finding MetaEditor..."

$possiblePaths = @(
    "C:\Program Files\MetaTrader 5\MetaEditor64.exe",
    "C:\Program Files (x86)\MetaTrader 5\MetaEditor64.exe",
    "C:\MT5\MetaTrader 5\MetaEditor64.exe",
    "C:\MT5\EC Markets MetaTrader 5\MetaEditor64.exe"
)

if ($MT5Path) {
    $possiblePaths = @("$MT5Path\MetaEditor64.exe") + $possiblePaths
}

$EditorPath = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $EditorPath = $path
        break
    }
}

# 妫€鏌?APPDATA 涓殑 MetaEditor
if (-not $EditorPath) {
    $appdataEditors = Get-ChildItem "${env:APPDATA}\MetaQuotes\Terminal" -Recurse -Filter "MetaEditor64.exe" -ErrorAction SilentlyContinue
    if ($appdataEditors) {
        $EditorPath = $appdataEditors[0].FullName
    }
}

if (-not $EditorPath) {
    Write-Host "ERROR: MetaEditor not found!"
    Write-Host "Searched paths:"
    $possiblePaths | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "Please specify MT5Path:"
    Write-Host "  .\scripts\build_ea.ps1 -MT5Path 'C:\Your\MT5\Path'"
    exit 1
}

Write-Host "  Found: $EditorPath"

# 妫€鏌ユ簮鏂囦欢
Write-Host ""
Write-Host "Step 2: Checking source file..."

if (-not (Test-Path $SourceFile)) {
    Write-Host "ERROR: Source file not found: $SourceFile"
    exit 1
}

$sourceInfo = Get-Item $SourceFile
Write-Host "  Source: $SourceFile"
Write-Host "  Size: $($sourceInfo.Length) bytes"

# 娓呯悊鏃ф枃浠?if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
    Write-Host "  Removed old output file"
}

# 缂栬瘧
Write-Host ""
Write-Host "Step 3: Compiling..."

$LogFile = Join-Path $ProjectRoot "compile.log"
$IncludePath = $ProjectRoot

Start-Process -FilePath $EditorPath `
    -ArgumentList "/compile:`"$SourceFile`"", "/log:`"$LogFile`"", "/include:`"$IncludePath`"" `
    -NoNewWindow -Wait

Start-Sleep -Seconds 3

# 妫€鏌ョ粨鏋?Write-Host ""
Write-Host "Step 4: Checking result..."

if (Test-Path $OutputFile) {
    $outputInfo = Get-Item $OutputFile
    Write-Host "  SUCCESS!"
    Write-Host "  Output: $OutputFile"
    Write-Host "  Size: $($outputInfo.Length) bytes"
    
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  Build completed successfully!"
    Write-Host "========================================"
} else {
    Write-Host "  FAILED!"
    
    if (Test-Path $LogFile) {
        Write-Host ""
        Write-Host "Compile Log:"
        Write-Host "----------------------------------------"
        Get-Content $LogFile -Encoding UTF8
        Write-Host "----------------------------------------"
    }
    
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  Build failed!"
    Write-Host "========================================"
    
    exit 1
}
