const mt5Input = document.getElementById("mt5File");
const btInput = document.getElementById("btFile");
const compareBtn = document.getElementById("compareBtn");
const toleranceInput = document.getElementById("tolerance");

const mt5CountEl = document.getElementById("mt5Count");
const btCountEl = document.getElementById("btCount");
const matchCountEl = document.getElementById("matchCount");
const diffCountEl = document.getElementById("diffCount");
const onlyMt5CountEl = document.getElementById("onlyMt5Count");
const onlyBtCountEl = document.getElementById("onlyBtCount");

const diffTableBody = document.querySelector("#diffTable tbody");
const onlyMt5Body = document.querySelector("#onlyMt5Table tbody");
const onlyBtBody = document.querySelector("#onlyBtTable tbody");

const state = {
  mt5: [],
  backtest: [],
};

function readFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsText(file);
  });
}

function parseJSON(text) {
  const data = JSON.parse(text);
  return Array.isArray(data) ? data : [];
}

function parseCSV(text) {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  if (lines.length < 2) {
    return [];
  }
  const headers = lines[0].split(",").map((h) => h.trim());
  return lines.slice(1).map((line) => {
    const values = line.split(",").map((v) => v.trim());
    const row = {};
    headers.forEach((header, index) => {
      row[header] = values[index] ?? "";
    });
    return row;
  });
}

function parseData(text) {
  try {
    return parseJSON(text);
  } catch (error) {
    return parseCSV(text);
  }
}

function normalizeSignal(raw) {
  return {
    time: raw.time ?? raw.Time ?? "",
    symbol: raw.symbol ?? raw.Symbol ?? "",
    type: raw.type ?? raw.Type ?? "",
    price: Number(raw.price ?? raw.Price ?? 0),
    sl: Number(raw.sl ?? raw.SL ?? raw.StopLoss ?? 0),
    tp: Number(raw.tp ?? raw.TP ?? raw.TakeProfit ?? 0),
    source: raw.source ?? raw.Source ?? "",
    timeframe: raw.timeframe ?? raw.Timeframe ?? raw.tf ?? "",
  };
}

function buildKey(signal, fields) {
  return fields.map((field) => signal[field] ?? "").join("|");
}

function getCheckedValues(selector) {
  return Array.from(document.querySelectorAll(selector))
    .filter((input) => input.checked)
    .map((input) => input.value);
}

function compareSignals() {
  const matchFields = getCheckedValues('input[type="checkbox"][value]');
  const keyFields = matchFields.filter((field) =>
    ["time", "symbol", "type", "source"].includes(field)
  );
  const compareFields = matchFields.filter((field) =>
    ["price", "sl", "tp", "timeframe"].includes(field)
  );
  const tolerance = Number(toleranceInput.value || 0);

  const mt5Signals = state.mt5.map(normalizeSignal);
  const btSignals = state.backtest.map(normalizeSignal);

  const mt5Map = new Map();
  mt5Signals.forEach((signal) => {
    const key = buildKey(signal, keyFields);
    const list = mt5Map.get(key) ?? [];
    list.push(signal);
    mt5Map.set(key, list);
  });

  const diffs = [];
  const matches = [];
  const onlyBacktest = [];

  btSignals.forEach((signal) => {
    const key = buildKey(signal, keyFields);
    const list = mt5Map.get(key);
    if (!list || list.length === 0) {
      onlyBacktest.push(signal);
      return;
    }
    const mt5Signal = list.shift();
    if (list.length === 0) {
      mt5Map.delete(key);
    }

    let hasDiff = false;
    compareFields.forEach((field) => {
      const mt5Value = mt5Signal[field];
      const btValue = signal[field];
      if (typeof mt5Value === "number" && typeof btValue === "number") {
        if (Math.abs(mt5Value - btValue) > tolerance) {
          hasDiff = true;
          diffs.push({
            key,
            field,
            mt5Value,
            btValue,
          });
        }
      } else if (mt5Value !== btValue) {
        hasDiff = true;
        diffs.push({
          key,
          field,
          mt5Value,
          btValue,
        });
      }
    });

    if (!hasDiff) {
      matches.push(key);
    }
  });

  const onlyMt5 = Array.from(mt5Map.values()).flat();

  renderSummary(mt5Signals.length, btSignals.length, matches.length, diffs.length, onlyMt5.length, onlyBacktest.length);
  renderDiffTable(diffs);
  renderSignalTable(onlyMt5Body, onlyMt5);
  renderSignalTable(onlyBtBody, onlyBacktest);
}

function renderSummary(mt5Count, btCount, matchCount, diffCount, onlyMt5Count, onlyBtCount) {
  mt5CountEl.textContent = mt5Count;
  btCountEl.textContent = btCount;
  matchCountEl.textContent = matchCount;
  diffCountEl.textContent = diffCount;
  onlyMt5CountEl.textContent = onlyMt5Count;
  onlyBtCountEl.textContent = onlyBtCount;
}

function renderDiffTable(rows) {
  diffTableBody.innerHTML = "";
  if (rows.length === 0) {
    diffTableBody.innerHTML = "<tr><td colspan=\"4\">暂无差异</td></tr>";
    return;
  }
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${row.key}</td>
      <td>${row.field}</td>
      <td>${row.mt5Value}</td>
      <td>${row.btValue}</td>
    `;
    diffTableBody.appendChild(tr);
  });
}

function renderSignalTable(targetBody, rows) {
  targetBody.innerHTML = "";
  if (rows.length === 0) {
    targetBody.innerHTML = "<tr><td colspan=\"7\">暂无记录</td></tr>";
    return;
  }
  rows.forEach((row) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${row.time}</td>
      <td>${row.symbol}</td>
      <td>${row.type}</td>
      <td>${row.price}</td>
      <td>${row.sl}</td>
      <td>${row.tp}</td>
      <td>${row.source}</td>
    `;
    targetBody.appendChild(tr);
  });
}

mt5Input.addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  const text = await readFile(file);
  state.mt5 = parseData(text);
});

btInput.addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (!file) return;
  const text = await readFile(file);
  state.backtest = parseData(text);
});

compareBtn.addEventListener("click", compareSignals);
