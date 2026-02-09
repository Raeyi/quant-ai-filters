param(
    [string]$Config = ".\\Python\\config.json",
    [string]$Source = "mt5",
    [string]$Data = "",
    [string]$DataPattern = "*.csv",
    [string]$Symbol = "XAUUSD",
    [string]$Timeframe = "M5",
    [string]$OutDir = "data",
    [int]$LabelShift = 1,
    [string]$Resample = "",
    [string]$Tz = "",
    [string]$Filter = "identity",
    [double]$ZscoreThreshold = 0.5,
    [string]$Mt5Signals = "",
    [string]$Profile = "",
    [switch]$AutoProfile,
    [string]$EntryMode = "",
    [Nullable[int]]$StartHour = $null,
    [Nullable[int]]$EndHour = $null,
    [Nullable[int]]$BollPeriod = $null,
    [Nullable[double]]$BollDev = $null,
    [Nullable[int]]$AtrPeriod = $null,
    [Nullable[int]]$ShortestClosingTime = $null,
    [Nullable[double]]$StructAtrSl = $null,
    [Nullable[double]]$VolAtrSl = $null,
    [Nullable[double]]$MidAtrTp = $null,
    [Nullable[double]]$MidAtrTp2 = $null,
    [Nullable[double]]$UplowAtrTp = $null,
    [Nullable[int]]$MaPeriod = $null,
    [Nullable[int]]$ProgressStep = $null,
    [Nullable[int]]$GapCooldownBars = $null,
    [Nullable[double]]$GapThresholdMultiplier = $null
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Config)) {
    Write-Host "ERROR: Config not found: $Config" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}
$outDirFull = (Resolve-Path $OutDir).Path

$cfg = Get-Content -Path $Config -Raw | ConvertFrom-Json

function Get-ProfileObject([string]$Name) {
    if ($cfg.profiles -and $cfg.profiles.PSObject.Properties.Name -contains $Name) {
        return $cfg.profiles.$Name
    }
    return $cfg
}

function Get-Mt5Root([object]$ProfileObj) {
    if ($ProfileObj.paths -and $ProfileObj.paths.mt5_root) {
        return [string]$ProfileObj.paths.mt5_root
    }
    return ""
}

function Resolve-RelativePath([string]$Root, [string]$FullPath) {
    try {
        $rootFull = (Resolve-Path $Root).Path
        $fileFull = (Resolve-Path $FullPath).Path
        if ($fileFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $fileFull.Substring($rootFull.Length).TrimStart("\", "/")
        }
    } catch {
        return ""
    }
    return ""
}

$activeProfile = $cfg.active_profile
if ($Profile) {
    $activeProfile = $Profile
}

if ($AutoProfile) {
    $candidateProfiles = @()
    if ($cfg.profiles) {
        $candidateProfiles = $cfg.profiles.PSObject.Properties.Name
    } elseif ($activeProfile) {
        $candidateProfiles = @($activeProfile)
    }

    if (-not $candidateProfiles -or $candidateProfiles.Count -eq 0) {
        $candidateProfiles = @("")
    }

    if ($Data) {
        $found = @()
        foreach ($p in $candidateProfiles) {
            $profileObj = Get-ProfileObject $p
            $root = Get-Mt5Root $profileObj
            if ($root) {
                $candidatePath = Join-Path $root $Data
                if (Test-Path $candidatePath) {
                    $found += [pscustomobject]@{ Profile = $p; FullPath = $candidatePath }
                }
            }
        }

        if ($found.Count -eq 1) {
            $activeProfile = $found[0].Profile
            Write-Host "AutoProfile: selected '$activeProfile' (file exists)" -ForegroundColor Yellow
        } elseif ($found.Count -gt 1) {
            $latest = $found | Sort-Object { (Get-Item $_.FullPath).LastWriteTime } -Descending | Select-Object -First 1
            $activeProfile = $latest.Profile
            Write-Host "AutoProfile: selected '$activeProfile' (newest file)" -ForegroundColor Yellow
        }
    } else {
        $candidates = @()
        foreach ($p in $candidateProfiles) {
            $profileObj = Get-ProfileObject $p
            $root = Get-Mt5Root $profileObj
            if (-not $root -or -not (Test-Path $root)) {
                continue
            }
            $latest = Get-ChildItem -Path $root -Filter $DataPattern -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($latest) {
                $candidates += [pscustomobject]@{ Profile = $p; File = $latest; Root = $root }
            }
        }

        if ($candidates.Count -gt 0) {
            $pick = $candidates | Sort-Object { $_.File.LastWriteTime } -Descending | Select-Object -First 1
            $activeProfile = $pick.Profile
            $rel = Resolve-RelativePath $pick.Root $pick.File.FullName
            $Data = if ($rel) { $rel } else { $pick.File.Name }
            Write-Host "AutoProfile: selected '$activeProfile' with latest CSV '$Data'" -ForegroundColor Yellow
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Data)) {
    Write-Host "ERROR: -Data is required (CSV filename or path relative to mt5_root)" -ForegroundColor Red
    exit 1
}

$cleanupTemp = $false
if ($activeProfile -and ($cfg.active_profile -ne $activeProfile)) {
    $cfg.active_profile = $activeProfile
    $tempConfig = [System.IO.Path]::GetTempFileName()
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $tempConfig -Encoding UTF8
    $Config = $tempConfig
    $cleanupTemp = $true
    Write-Host "Using profile '$activeProfile' (temporary config: $tempConfig)" -ForegroundColor Yellow
}

$featuresPath = Join-Path $outDirFull "features.csv"
$signalsPath = Join-Path $outDirFull "signals.csv"
$datasetPath = Join-Path $outDirFull "dataset.csv"
$diffPath = Join-Path $outDirFull "signal_diff.csv"
$equityPath = Join-Path $outDirFull "equity.csv"

$args = @(
    ".\\Python\\backtest.py",
    "--config", $Config,
    "--source", $Source,
    "--data", $Data,
    "--symbol", $Symbol,
    "--timeframe", $Timeframe,
    "--export-features", $featuresPath,
    "--export-signals", $signalsPath,
    "--export-equity", $equityPath,
    "--filter", $Filter,
    "--zscore-threshold", $ZscoreThreshold
)

if ($Resample) {
    $args += @("--resample", $Resample)
}
if ($Tz) {
    $args += @("--tz", $Tz)
}

if ($EntryMode) {
    $args += @("--entry-mode", $EntryMode)
}
if ($StartHour -ne $null) {
    $args += @("--start-hour", $StartHour)
}
if ($EndHour -ne $null) {
    $args += @("--end-hour", $EndHour)
}
if ($BollPeriod -ne $null) {
    $args += @("--boll-period", $BollPeriod)
}
if ($BollDev -ne $null) {
    $args += @("--boll-dev", $BollDev)
}
if ($AtrPeriod -ne $null) {
    $args += @("--atr-period", $AtrPeriod)
}
if ($ShortestClosingTime -ne $null) {
    $args += @("--shortest-closing-time", $ShortestClosingTime)
}
if ($StructAtrSl -ne $null) {
    $args += @("--struct-atr-sl", $StructAtrSl)
}
if ($VolAtrSl -ne $null) {
    $args += @("--vol-atr-sl", $VolAtrSl)
}
if ($MidAtrTp -ne $null) {
    $args += @("--mid-atr-tp", $MidAtrTp)
}
if ($MidAtrTp2 -ne $null) {
    $args += @("--mid-atr-tp2", $MidAtrTp2)
}
if ($UplowAtrTp -ne $null) {
    $args += @("--uplow-atr-tp", $UplowAtrTp)
}
if ($MaPeriod -ne $null) {
    $args += @("--ma-period", $MaPeriod)
}
if ($GapCooldownBars -ne $null) {
    $args += @("--gap-cooldown-bars", $GapCooldownBars)
}
if ($GapThresholdMultiplier -ne $null) {
    $args += @("--gap-threshold-multiplier", $GapThresholdMultiplier)
}
if ($ProgressStep -ne $null -and $ProgressStep -gt 0) {
    $args += @("--progress-step", $ProgressStep)
}

Write-Host "Running backtest..." -ForegroundColor Cyan
python @args

Write-Host "Building dataset..." -ForegroundColor Cyan
python .\\Python\\utils\\build_dataset.py --features $featuresPath --signals $signalsPath --out $datasetPath --label-shift $LabelShift

if ($Mt5Signals) {
    if (-not (Test-Path $Mt5Signals)) {
        Write-Host "WARN: MT5 signals file not found: $Mt5Signals" -ForegroundColor Yellow
    } else {
        Write-Host "Comparing signals..." -ForegroundColor Cyan
        python .\\Python\\utils\\compare_signals.py --python $signalsPath --mt5 $Mt5Signals --out $diffPath
    }
}

Write-Host "Done." -ForegroundColor Green

if ($cleanupTemp -and (Test-Path $Config)) {
    Remove-Item -Path $Config -Force
}
