from __future__ import annotations

import argparse
import cgi
import csv
import json
import subprocess
import sys
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Tuple
from urllib.parse import parse_qs, urlparse

ROOT_DIR = Path(__file__).resolve().parents[2]
CONFIG_PATH = ROOT_DIR / "Python" / "config.json"
RUN_PIPELINE = ROOT_DIR / "scripts" / "run_pipeline.ps1"

INDEX_HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Quant AI Filters - Web Panel</title>
  <style>
    :root {
      --bg: #0f1417;
      --panel: #151c21;
      --panel-2: #1b242b;
      --text: #e7edf2;
      --muted: #9fb0bd;
      --accent: #52b788;
      --accent-2: #4ea8de;
      --danger: #e06c75;
      --border: #24303a;
      --code: #0b0f12;
      --shadow: 0 12px 30px rgba(0,0,0,0.35);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
      color: var(--text);
      background: radial-gradient(1200px 600px at 10% -10%, #1b2a2f 0%, #0f1417 60%) fixed;
    }
    header {
      padding: 20px 28px;
      border-bottom: 1px solid var(--border);
      background: linear-gradient(90deg, #151c21, #0f1417);
    }
    .head-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      flex-wrap: wrap;
    }
    header h1 { margin: 0 0 6px; font-size: 22px; }
    header p { margin: 0; color: var(--muted); }
    .nav {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }
    .nav-btn {
      background: transparent;
      border: 1px solid var(--border);
      color: var(--text);
      padding: 8px 14px;
      border-radius: 999px;
      cursor: pointer;
      font-size: 13px;
    }
    .nav-btn.active {
      border-color: #2d6a4f;
      background: linear-gradient(135deg, var(--accent), #2d6a4f);
    }
    .page { display: none; }
    .page.active { display: block; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 16px;
      padding: 20px;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 16px;
      box-shadow: var(--shadow);
    }
    .card h2 { margin: 0 0 12px; font-size: 16px; }
    label { display: block; font-size: 12px; color: var(--muted); margin: 10px 0 6px; }
    input, select, textarea, button {
      width: 100%;
      padding: 8px 10px;
      border-radius: 8px;
      border: 1px solid var(--border);
      background: var(--panel-2);
      color: var(--text);
      font-size: 13px;
    }
    textarea { min-height: 120px; font-family: "JetBrains Mono", Consolas, monospace; }
    button {
      cursor: pointer;
      background: linear-gradient(135deg, var(--accent), #2d6a4f);
      border: none;
      font-weight: 600;
      margin-top: 10px;
    }
    button.secondary { background: linear-gradient(135deg, var(--accent-2), #3a86ff); }
    button.ghost { background: transparent; border: 1px solid var(--border); color: var(--text); }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .muted { color: var(--muted); font-size: 12px; }
    .log {
      background: var(--code);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 10px;
      white-space: pre-wrap;
      max-height: 260px;
      overflow: auto;
      font-family: "JetBrains Mono", Consolas, monospace;
      font-size: 12px;
    }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th, td { padding: 6px 8px; border-bottom: 1px solid var(--border); text-align: left; }
    .pill {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 999px;
      background: #20323a;
      font-size: 11px;
      color: var(--muted);
    }
    .chart {
      width: 100%;
      height: 180px;
      background: #0b0f12;
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 6px;
    }
    .actions { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 8px; }
  </style>
</head>
<body>
  <header>
    <div class="head-row">
      <div>
        <h1>Quant AI Filters - Web Panel</h1>
        <p>Compare MT5 vs Backtest signals, run pipelines, and manage configs.</p>
      </div>
      <nav class="nav">
        <button class="nav-btn" data-page="home">Home</button>
        <button class="nav-btn" data-page="backtest">Backtest</button>
        <button class="nav-btn" data-page="compare">Compare</button>
      </nav>
    </div>
  </header>

  <section id="page-home" class="page active">
    <div class="grid">
      <section class="card">
        <h2>Profile & Config</h2>
        <label>Active Profile</label>
        <select id="profileSelect"></select>
        <label>Config JSON</label>
        <textarea id="configJson"></textarea>
        <div class="actions">
          <button id="reloadConfig" class="ghost">Reload</button>
          <button id="saveConfig">Save Config</button>
        </div>
        <div class="muted" id="configStatus"></div>
      </section>

      <section class="card">
        <h2>MT5 CSV List</h2>
        <label>Pattern</label>
        <input id="listPattern" value="*.csv" />
        <button id="listCsv" class="ghost">Refresh List</button>
        <div class="muted" id="listStatus"></div>
        <div style="max-height:240px; overflow:auto;">
          <table>
            <thead><tr><th>Name</th><th>Size KB</th><th>Modified</th></tr></thead>
            <tbody id="csvTable"></tbody>
          </table>
        </div>
      </section>

      <section class="card">
        <h2>Upload CSV</h2>
        <input id="uploadFile" type="file" />
        <button id="uploadBtn" class="ghost">Upload</button>
        <div class="muted" id="uploadStatus"></div>
      </section>

      <section class="card">
        <h2>Export/Download</h2>
        <label>Export .set by Profile</label>
        <input id="exportProfile" placeholder="backtest" />
        <button id="exportSet" class="ghost">Download .set</button>
        <label>Download MT5 File by Name</label>
        <input id="downloadMt5Name" placeholder="signals_mt5.csv" />
        <button id="downloadMt5" class="ghost">Download MT5 CSV</button>
      </section>
    </div>
  </section>

  <section id="page-backtest" class="page">
    <div class="grid">
      <section class="card">
        <h2>Run Pipeline</h2>
        <div class="row">
          <div>
            <label>Data (CSV file name or path)</label>
            <input id="runData" placeholder="XAUUSD_M5.csv" />
          </div>
          <div>
            <label>Source</label>
            <select id="runSource">
              <option value="mt5">mt5</option>
              <option value="dukascopy">dukascopy</option>
              <option value="truefx">truefx</option>
            </select>
          </div>
        </div>
        <div class="row">
          <div><label>Symbol</label><input id="runSymbol" value="XAUUSD" /></div>
          <div><label>Timeframe</label><input id="runTimeframe" value="M5" /></div>
        </div>
        <div class="row">
          <div><label>Out Dir</label><input id="runOutDir" value="data" /></div>
          <div><label>Filter</label><input id="runFilter" value="identity" /></div>
        </div>
        <div class="row">
          <div><label>Zscore Threshold</label><input id="runZscore" value="0.5" /></div>
          <div><label>Data Pattern</label><input id="runPattern" value="*.csv" /></div>
        </div>
        <div class="row">
          <div><label>MT5 Signals (optional)</label><input id="runMt5Signals" placeholder="signals_mt5.csv" /></div>
          <div><label>Resample (optional)</label><input id="runResample" placeholder="5T" /></div>
        </div>
        <div class="row">
          <div><label>Timezone (optional)</label><input id="runTz" placeholder="UTC+0" /></div>
          <div><label>Profile (optional)</label><input id="runProfile" placeholder="backtest" /></div>
        </div>
        <label><input id="runAutoProfile" type="checkbox" /> Auto Profile</label>
        <button id="runPipeline" class="secondary">Run</button>
        <div class="muted" id="runStatus"></div>
      </section>

      <section class="card">
        <h2>Backtest Stats</h2>
        <div id="stats"></div>
        <div class="chart">
          <svg id="equityChart" viewBox="0 0 600 180" width="100%" height="100%"></svg>
        </div>
        <label>Run Log</label>
        <div class="log" id="runLog"></div>
      </section>
    </div>
  </section>

  <section id="page-compare" class="page">
    <div class="grid">
      <section class="card">
        <h2>Compare Signals</h2>
        <label>Python Signals (CSV)</label>
        <input id="cmpPython" placeholder="signals.csv" />
        <label>MT5 Signals (CSV)</label>
        <input id="cmpMt5" placeholder="signals_mt5.csv" />
        <label>Output Diff Path</label>
        <input id="cmpOut" value="data/signal_diff.csv" />
        <div class="row">
          <div><label>Start Time</label><input id="cmpStart" placeholder="2025-01-01 00:00:00" /></div>
          <div><label>End Time</label><input id="cmpEnd" placeholder="2025-02-01 00:00:00" /></div>
        </div>
        <div class="row">
          <div><label>Drop First</label><input id="cmpDropFirst" placeholder="50" /></div>
          <div><label>Drop Last</label><input id="cmpDropLast" placeholder="50" /></div>
        </div>
        <label><input id="cmpEventOnly" type="checkbox" /> Event Only</label>
        <button id="runCompare">Compare</button>
        <div class="muted" id="compareStatus"></div>
      </section>

      <section class="card">
        <h2>Compare Log</h2>
        <div class="log" id="compareLog"></div>
      </section>
    </div>
  </section>

  <script>
    const el = (id) => document.getElementById(id);
    const fmt = (v) => (v === null || v === undefined) ? "" : String(v);
    const pages = ["home", "backtest", "compare"];

    function setActivePage(name) {
      pages.forEach(p => {
        const pageEl = el("page-" + p);
        if (pageEl) pageEl.classList.toggle("active", p === name);
      });
      document.querySelectorAll(".nav-btn").forEach(btn => {
        btn.classList.toggle("active", btn.dataset.page === name);
      });
    }

    function currentPage() {
      const h = (location.hash || "").replace("#", "");
      return pages.includes(h) ? h : "home";
    }

    function syncPage() {
      const p = currentPage();
      setActivePage(p);
    }

    function drawEquity(points) {
      const svg = el("equityChart");
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      if (!points || points.length === 0) {
        const t = document.createElementNS("http://www.w3.org/2000/svg", "text");
        t.setAttribute("x", "10");
        t.setAttribute("y", "20");
        t.setAttribute("fill", "#9fb0bd");
        t.setAttribute("font-size", "12");
        t.textContent = "No equity data";
        svg.appendChild(t);
        return;
      }
      const values = points.map(p => p.equity);
      const min = Math.min(...values);
      const max = Math.max(...values);
      const w = 600;
      const h = 180;
      const pad = 10;
      const range = (max - min) || 1;
      let d = "";
      points.forEach((p, i) => {
        const x = pad + (i / (points.length - 1 || 1)) * (w - pad * 2);
        const y = h - pad - ((p.equity - min) / range) * (h - pad * 2);
        d += (i === 0 ? "M" : "L") + x.toFixed(2) + " " + y.toFixed(2) + " ";
      });
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d.trim());
      path.setAttribute("stroke", "#52b788");
      path.setAttribute("stroke-width", "2");
      path.setAttribute("fill", "none");
      svg.appendChild(path);
    }

    async function loadConfig() {
      const res = await fetch("/api/config");
      const data = await res.json();
      el("configJson").value = JSON.stringify(data.config || {}, null, 2);
      const profiles = data.profiles || [];
      const select = el("profileSelect");
      select.innerHTML = "";
      profiles.forEach(p => {
        const opt = document.createElement("option");
        opt.value = p;
        opt.textContent = p;
        if (p === data.active_profile) opt.selected = true;
        select.appendChild(opt);
      });
      el("configStatus").textContent = "Loaded profile: " + fmt(data.active_profile);
    }

    async function saveConfig() {
      let cfg;
      try {
        cfg = JSON.parse(el("configJson").value || "{}");
      } catch (e) {
        el("configStatus").textContent = "Invalid JSON: " + e.message;
        return;
      }
      const res = await fetch("/api/config", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ config: cfg })
      });
      const data = await res.json();
      el("configStatus").textContent = data.ok ? "Saved" : ("Save failed: " + fmt(data.error));
    }

    async function listCsv() {
      const profile = el("profileSelect").value || "";
      const pattern = encodeURIComponent(el("listPattern").value || "*.csv");
      const res = await fetch(`/api/list-csv?profile=${encodeURIComponent(profile)}&pattern=${pattern}`);
      const data = await res.json();
      el("listStatus").textContent = data.exists ? ("Root: " + data.root) : "Root missing or not set";
      const tbody = el("csvTable");
      tbody.innerHTML = "";
      (data.files || []).forEach(f => {
        const tr = document.createElement("tr");
        tr.innerHTML = `<td>${f.name}</td><td>${f.size_kb}</td><td>${f.mtime}</td>`;
        tr.addEventListener("click", () => {
          el("runData").value = f.name;
          location.hash = "backtest";
          syncPage();
        });
        tbody.appendChild(tr);
      });
    }

    async function runPipeline() {
      el("runStatus").textContent = "Running...";
      const payload = {
        data: el("runData").value,
        source: el("runSource").value,
        symbol: el("runSymbol").value,
        timeframe: el("runTimeframe").value,
        out_dir: el("runOutDir").value,
        filter: el("runFilter").value,
        zscore_threshold: parseFloat(el("runZscore").value || "0.5"),
        data_pattern: el("runPattern").value || "*.csv",
        mt5_signals: el("runMt5Signals").value,
        resample: el("runResample").value,
        tz: el("runTz").value,
        profile: el("runProfile").value,
        auto_profile: el("runAutoProfile").checked
      };
      const res = await fetch("/api/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      el("runStatus").textContent = data.ok ? "Success" : ("Failed: " + fmt(data.error));
      el("runLog").textContent = data.log || "";
      const stats = data.stats || {};
      const statLines = Object.keys(stats).map(k => `<div><span class="pill">${k}</span> ${stats[k]}</div>`);
      el("stats").innerHTML = statLines.join("");
      drawEquity(data.equity || []);
    }

    async function runCompare() {
      el("compareStatus").textContent = "Comparing...";
      const payload = {
        python_signals: el("cmpPython").value,
        mt5_signals: el("cmpMt5").value,
        out_path: el("cmpOut").value,
        start_time: el("cmpStart").value,
        end_time: el("cmpEnd").value,
        drop_first: el("cmpDropFirst").value,
        drop_last: el("cmpDropLast").value,
        event_only: el("cmpEventOnly").checked
      };
      const res = await fetch("/api/compare", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      el("compareStatus").textContent = data.ok ? "Done" : ("Failed: " + fmt(data.error));
      el("compareLog").textContent = data.log || "";
    }

    async function uploadCsv() {
      const file = el("uploadFile").files[0];
      if (!file) {
        el("uploadStatus").textContent = "Choose a file first";
        return;
      }
      const form = new FormData();
      form.append("file", file);
      const res = await fetch("/api/upload-csv", { method: "POST", body: form });
      const data = await res.json();
      el("uploadStatus").textContent = data.ok ? ("Saved: " + data.saved) : ("Upload failed: " + fmt(data.error));
    }

    function downloadSet() {
      const profile = encodeURIComponent(el("exportProfile").value || "");
      window.location = `/api/export-set?profile=${profile}`;
    }

    function downloadMt5() {
      const name = encodeURIComponent(el("downloadMt5Name").value || "");
      const profile = encodeURIComponent(el("profileSelect").value || "");
      window.location = `/api/download-mt5?profile=${profile}&name=${name}`;
    }

    document.querySelectorAll(".nav-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        location.hash = btn.dataset.page;
        syncPage();
      });
    });
    window.addEventListener("hashchange", syncPage);

    el("reloadConfig").addEventListener("click", loadConfig);
    el("saveConfig").addEventListener("click", saveConfig);
    el("listCsv").addEventListener("click", listCsv);
    el("runPipeline").addEventListener("click", runPipeline);
    el("runCompare").addEventListener("click", runCompare);
    el("uploadBtn").addEventListener("click", uploadCsv);
    el("exportSet").addEventListener("click", downloadSet);
    el("downloadMt5").addEventListener("click", downloadMt5);

    syncPage();
    loadConfig().then(listCsv).catch(err => {
      el("configStatus").textContent = "Load failed: " + err.message;
    });
  </script>
</body>
</html>
"""


def _load_config() -> Dict[str, Any]:
    if not CONFIG_PATH.exists():
        return {}
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))


def _save_config(cfg: Dict[str, Any]) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


def _get_profile(cfg: Dict[str, Any], name: str = "") -> Tuple[str, Dict[str, Any]]:
    active = name or cfg.get("active_profile", "")
    profiles = cfg.get("profiles", {})
    if active and isinstance(profiles, dict) and active in profiles:
        return active, profiles[active]
    return "", cfg


def _resolve_path(root: str, path: str) -> Path:
    p = Path(path)
    if p.is_absolute():
        return p
    if not root:
        return (ROOT_DIR / p).resolve()
    return (Path(root) / p).resolve()


def _list_csv_files(root: str, pattern: str) -> List[Dict[str, Any]]:
    if not root:
        return []
    p = Path(root)
    if not p.exists():
        return []
    files = sorted(p.glob(pattern), key=lambda x: x.stat().st_mtime, reverse=True)
    result = []
    for f in files[:200]:
        stat = f.stat()
        result.append(
            {
                "name": f.name,
                "mtime": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(stat.st_mtime)),
                "size_kb": int(stat.st_size / 1024),
            }
        )
    return result


def _config_to_set(profile: Dict[str, Any]) -> str:
    strat = ((profile.get("strategy") or {}).get("boll_mr") or {})
    mapping = [
        ("boll_Allowed_transaction_start_time", strat.get("allowed_start_hour", 2)),
        ("boll_Allowed_transaction_end_time", strat.get("allowed_end_hour", 20)),
        ("BollPeriod", strat.get("boll_period", 20)),
        ("BollDev", strat.get("boll_dev", 2.0)),
        ("ATRPeriod", strat.get("atr_period", 14)),
        ("ShortestClosingTime", strat.get("shortest_closing_time", 10)),
        ("StructATRSL", strat.get("struct_atr_sl", 0.8)),
        ("VolATRSL", strat.get("vol_atr_sl", 2.0)),
        ("BoolMidATRTP", strat.get("mid_atr_tp", 0.2)),
        ("BoolUplowATRTP", strat.get("uplow_atr_tp", 0.1)),
        ("MAPeriod", strat.get("ma_period", 50)),
        ("boll_entry_mode", strat.get("entry_mode", "A")),
    ]
    lines = [f"{k}={v}" for k, v in mapping]
    return "\n".join(lines) + "\n"


def _parse_set(text: str) -> Dict[str, str]:
    params: Dict[str, str] = {}
    for line in text.splitlines():
        raw = line.strip()
        if not raw or raw.startswith(";") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        if "," in key:
            continue
        params[key.strip()] = value.strip()
    return params


def _apply_set_to_profile(profile: Dict[str, Any], params: Dict[str, str]) -> None:
    profile.setdefault("strategy", {})
    profile["strategy"].setdefault("boll_mr", {})
    target = profile["strategy"]["boll_mr"]
    mapping = {
        "boll_Allowed_transaction_start_time": ("allowed_start_hour", int),
        "boll_Allowed_transaction_end_time": ("allowed_end_hour", int),
        "BollPeriod": ("boll_period", int),
        "BollDev": ("boll_dev", float),
        "ATRPeriod": ("atr_period", int),
        "ShortestClosingTime": ("shortest_closing_time", int),
        "StructATRSL": ("struct_atr_sl", float),
        "VolATRSL": ("vol_atr_sl", float),
        "BoolMidATRTP": ("mid_atr_tp", float),
        "BoolUplowATRTP": ("uplow_atr_tp", float),
        "MAPeriod": ("ma_period", int),
        "boll_entry_mode": ("entry_mode", str),
    }
    for key, (cfg_key, cast) in mapping.items():
        if key in params:
            try:
                target[cfg_key] = cast(params[key])
            except ValueError:
                continue


def _resolve_path_or_common(value: str, data_root: str, mt5_common_root: str) -> str:
    p = Path(value)
    if p.is_absolute():
        return str(p)
    if data_root:
        cand = Path(data_root) / value
        if cand.exists():
            return str(cand)
    if mt5_common_root:
        cand = Path(mt5_common_root) / value
        if cand.exists():
            return str(cand)
    return str((ROOT_DIR / value).resolve())


def _read_equity_csv(path: Path, max_points: int = 1500) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    rows: List[Dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                rows.append(
                    {
                        "time": row.get("time", ""),
                        "equity": float(row.get("equity", "0") or 0),
                        "returns": float(row.get("returns", "0") or 0),
                    }
                )
            except ValueError:
                continue
    if len(rows) <= max_points:
        return rows
    step = max(1, int(len(rows) / max_points))
    return rows[::step]


def _parse_stats_from_log(log: str) -> Dict[str, Any]:
    stats: Dict[str, Any] = {}
    in_stats = False
    for line in log.splitlines():
        if "Backtest stats" in line:
            in_stats = True
            continue
        if in_stats:
            if not line.strip():
                break
            if ":" in line:
                key, value = line.split(":", 1)
                key = key.strip()
                value = value.strip()
                try:
                    if key == "trades":
                        stats[key] = int(float(value))
                    else:
                        stats[key] = float(value) if value else value
                except ValueError:
                    stats[key] = value
    return stats


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, data: Dict[str, Any], status: int = 200) -> None:
        payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _send_text(self, text: str, status: int = 200) -> None:
        payload = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _send_file(self, path: Path, filename: str, content_type: str) -> None:
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._send_text(INDEX_HTML)
            return
        if parsed.path == "/api/config":
            cfg = _load_config()
            active, profile = _get_profile(cfg)
            profiles = list((cfg.get("profiles") or {}).keys())
            self._send_json(
                {
                    "config": cfg,
                    "active_profile": active,
                    "profile": profile,
                    "profiles": profiles,
                }
            )
            return
        if parsed.path == "/api/list-csv":
            cfg = _load_config()
            qs = parse_qs(parsed.query)
            profile_name = qs.get("profile", [""])[0]
            pattern = qs.get("pattern", ["*.csv"])[0] or "*.csv"
            _, profile = _get_profile(cfg, profile_name)
            root = (profile.get("paths") or {}).get("mt5_root", "")
            exists = bool(root) and Path(root).exists()
            files = _list_csv_files(root, pattern) if exists else []
            self._send_json({"root": root, "exists": exists, "files": files})
            return
        if parsed.path == "/api/export-set":
            cfg = _load_config()
            qs = parse_qs(parsed.query)
            profile_name = qs.get("profile", [""])[0]
            _, profile = _get_profile(cfg, profile_name)
            content = _config_to_set(profile)
            temp = ROOT_DIR / "data" / "export.set"
            temp.parent.mkdir(parents=True, exist_ok=True)
            temp.write_text(content, encoding="utf-8")
            name = f"{profile_name or 'profile'}.set"
            self._send_file(temp, name, "text/plain; charset=utf-8")
            return
        if parsed.path == "/api/download-mt5":
            cfg = _load_config()
            qs = parse_qs(parsed.query)
            profile_name = qs.get("profile", [""])[0]
            name = Path(qs.get("name", [""])[0]).name
            _, profile = _get_profile(cfg, profile_name)
            root = (profile.get("paths") or {}).get("mt5_common_root", "")
            if not root or not name:
                self._send_json({"ok": False, "error": "mt5_common_root 或文件名为空"}, status=400)
                return
            path = Path(root) / name
            if not path.exists():
                self._send_json({"ok": False, "error": f"文件不存在: {path}"}, status=404)
                return
            self._send_file(path, name, "text/csv; charset=utf-8")
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not Found")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/config":
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length).decode("utf-8") if length else "{}"
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                self._send_json({"ok": False, "error": "JSON 解析失败"}, status=400)
                return
            cfg = payload.get("config")
            if not isinstance(cfg, dict):
                self._send_json({"ok": False, "error": "config 格式错误"}, status=400)
                return
            _save_config(cfg)
            self._send_json({"ok": True})
            return

        if parsed.path == "/api/run":
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length).decode("utf-8") if length else "{}"
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                self._send_json({"ok": False, "error": "JSON 解析失败"}, status=400)
                return
            data = payload.get("data", "").strip()
            if not data:
                self._send_json({"ok": False, "error": "Data 不能为空"}, status=400)
                return
            args = [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(RUN_PIPELINE),
                "-Config",
                str(CONFIG_PATH),
                "-Source",
                payload.get("source", "mt5"),
                "-Data",
                data,
                "-Symbol",
                payload.get("symbol", "XAUUSD"),
                "-Timeframe",
                payload.get("timeframe", "M5"),
                "-OutDir",
                payload.get("out_dir", "data"),
                "-Filter",
                payload.get("filter", "identity"),
                "-ZscoreThreshold",
                str(payload.get("zscore_threshold", 0.5)),
                "-DataPattern",
                payload.get("data_pattern", "*.csv"),
            ]

            if payload.get("profile"):
                args += ["-Profile", payload.get("profile")]
            if payload.get("auto_profile"):
                args += ["-AutoProfile"]

            optional_map = {
                "resample": "-Resample",
                "tz": "-Tz",
                "mt5_signals": "-Mt5Signals",
                "entry_mode": "-EntryMode",
                "allowed_start_hour": "-StartHour",
                "allowed_end_hour": "-EndHour",
                "boll_period": "-BollPeriod",
                "boll_dev": "-BollDev",
                "atr_period": "-AtrPeriod",
                "shortest_closing_time": "-ShortestClosingTime",
                "struct_atr_sl": "-StructAtrSl",
                "vol_atr_sl": "-VolAtrSl",
                "mid_atr_tp": "-MidAtrTp",
                "uplow_atr_tp": "-UplowAtrTp",
                "ma_period": "-MaPeriod",
                "progress_step": "-ProgressStep",
            }
            for key, flag in optional_map.items():
                value = payload.get(key, "")
                if value is None or value == "" or (value == 0 and key == "progress_step"):
                    continue
                args += [flag, str(value)]

            proc = subprocess.run(
                args,
                cwd=str(ROOT_DIR),
                capture_output=True,
                text=True,
            )
            log = (proc.stdout or "") + (proc.stderr or "")
            stats = _parse_stats_from_log(log)

            out_dir = payload.get("out_dir", "data")
            out_path = _resolve_path(str(ROOT_DIR), out_dir)
            equity_path = Path(out_path) / "equity.csv"
            equity = _read_equity_csv(equity_path)

            self._send_json(
                {
                    "ok": proc.returncode == 0,
                    "log": log,
                    "stats": stats,
                    "equity": equity,
                    "error": None if proc.returncode == 0 else "回测运行失败",
                }
            )
            return

        if parsed.path == "/api/upload-csv":
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={"REQUEST_METHOD": "POST", "CONTENT_TYPE": self.headers.get("Content-Type")},
            )
            if "file" not in form:
                self._send_json({"ok": False, "error": "未找到上传文件"}, status=400)
                return
            file_item = form["file"]
            if not file_item.filename:
                self._send_json({"ok": False, "error": "文件名为空"}, status=400)
                return
            cfg = _load_config()
            _, profile = _get_profile(cfg)
            data_root = (profile.get("paths") or {}).get("data_root", "data")
            save_dir = _resolve_path(str(ROOT_DIR), data_root)
            save_dir.mkdir(parents=True, exist_ok=True)
            filename = Path(file_item.filename).name
            dest = save_dir / filename
            with dest.open("wb") as f:
                f.write(file_item.file.read())
            self._send_json({"ok": True, "saved": str(dest)})
            return

        if parsed.path == "/api/import-set":
            form = cgi.FieldStorage(
                fp=self.rfile,
                headers=self.headers,
                environ={"REQUEST_METHOD": "POST", "CONTENT_TYPE": self.headers.get("Content-Type")},
            )
            if "file" not in form:
                self._send_json({"ok": False, "error": "未找到上传文件"}, status=400)
                return
            file_item = form["file"]
            content = file_item.file.read().decode("utf-8", errors="ignore")
            params = _parse_set(content)
            cfg = _load_config()
            profile_name = form.getvalue("profile", "")
            _, profile = _get_profile(cfg, profile_name)
            _apply_set_to_profile(profile, params)
            _save_config(cfg)
            self._send_json({"ok": True})
            return

        if parsed.path == "/api/compare":
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length).decode("utf-8") if length else "{}"
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                self._send_json({"ok": False, "error": "JSON 解析失败"}, status=400)
                return
            cfg = _load_config()
            profile_name = payload.get("profile", "")
            _, profile = _get_profile(cfg, profile_name)
            paths = profile.get("paths") or {}
            data_root = paths.get("data_root", "data")
            mt5_common_root = paths.get("mt5_common_root", "")

            py_path = _resolve_path_or_common(payload.get("python_signals", ""), data_root, mt5_common_root)
            mt5_path = _resolve_path_or_common(payload.get("mt5_signals", ""), data_root, mt5_common_root)
            out_path = _resolve_path_or_common(payload.get("out_path", "data/signal_diff.csv"), data_root, mt5_common_root)

            args = [
                sys.executable,
                str(ROOT_DIR / "Python" / "utils" / "compare_signals.py"),
                "--python",
                py_path,
                "--mt5",
                mt5_path,
                "--out",
                out_path,
            ]
            if payload.get("start_time"):
                args += ["--start-time", payload.get("start_time")]
            if payload.get("end_time"):
                args += ["--end-time", payload.get("end_time")]
            if payload.get("drop_first"):
                args += ["--drop-first", str(payload.get("drop_first"))]
            if payload.get("drop_last"):
                args += ["--drop-last", str(payload.get("drop_last"))]
            if payload.get("event_only"):
                args += ["--event-only"]

            proc = subprocess.run(args, cwd=str(ROOT_DIR), capture_output=True, text=True)
            log = (proc.stdout or "") + (proc.stderr or "")
            self._send_json(
                {
                    "ok": proc.returncode == 0,
                    "log": log,
                    "error": None if proc.returncode == 0 else "对比失败",
                }
            )
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not Found")


def main() -> None:
    parser = argparse.ArgumentParser(description="Quant AI Filters web UI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Web UI running at http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
