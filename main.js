/* ============================================================
   GLOBAL SOVEREIGN RISK — TERMINAL
   Rendering engine
   ============================================================ */

/* ---------- live CSV data loading ----------
   Loads Q1–Q10 CSVs from /data at runtime and parses them into the
   same DATA.Q1 … DATA.Q9a / DATA.Q9b shape the rest of this file
   expects. Requires the page to be served over http(s):// — browsers
   block fetch() of local files under file://. */
const CSV_FILES = {
  Q1:"Q1.csv", Q2:"Q2.csv", Q3:"Q3.csv", Q4:"Q4.csv",
  Q5:"Q5.csv", Q6:"Q6.csv", Q7:"Q7.csv", Q8:"Q8.csv",
  Q9a:"Q9a.csv", Q9b:"Q9b.csv", Q10:"Q10.csv"
};
const NUMERIC_RE = /^-?\d+(\.\d+)?$/;

/** Converts a raw parsed CSV cell to the same types pandas' to_dict
 *  would have produced: "NULL" -> null, numeric-looking strings -> Number,
 *  everything else stays a string. */
function coerceCsvValue(v){
  if(v === null || v === undefined) return null;
  const s = String(v).trim();
  if(s === "" || s.toUpperCase() === "NULL") return null;
  if(NUMERIC_RE.test(s)) return Number(s);
  return v;
}
function coerceCsvRow(row){
  const out = {};
  for(const k in row) out[k] = coerceCsvValue(row[k]);
  return out;
}

function loadCsv(path){
  return fetch(path)
    .then(res => {
      if(!res.ok) throw new Error(`${path} → HTTP ${res.status}`);
      return res.text();
    })
    .then(text => new Promise((resolve, reject) => {
      Papa.parse(text, {
        header:true,
        skipEmptyLines:true,
        complete: (results) => resolve(results.data.map(coerceCsvRow)),
        error: (err) => reject(new Error(`${path} → ${err.message || err}`))
      });
    }));
}

function loadAllData(){
  const keys = Object.keys(CSV_FILES);
  return Promise.all(keys.map(k => loadCsv(CSV_FILES[k])))
    .then(results => {
      const data = {};
      keys.forEach((k, i) => { data[k] = results[i]; });
      return data;
    });
}

let DATA = null; // populated by loadAllData() before boot

/* ---------- helpers ---------- */
function flagClass(flag){
  if(!flag) return "gray";
  const f = flag.toUpperCase();
  if(f.startsWith("RED")) return "red";
  if(f.startsWith("YELLOW") || f.startsWith("AMBER")) return "amber";
  if(f.startsWith("GREEN")) return "green";
  if(f.startsWith("BLUE")) return "blue";
  return "gray";
}
function flagLabel(flag){
  if(!flag) return "";
  return flag.replace(/^(RED|YELLOW|GREEN|BLUE)\s*-\s*/i, "");
}
const COLORS = { red:"#C4453A", amber:"#C08A3E", green:"#4C8B6C", blue:"#4472A8", gray:"#5B6270" };

function fmtNum(v, decimals=1){
  if(v === null || v === undefined || v === "" || (typeof v === "number" && Number.isNaN(v))) return "—";
  const n = Number(v);
  if(Number.isNaN(n)) return v;
  return n.toLocaleString("en-US", {minimumFractionDigits:decimals, maximumFractionDigits:decimals});
}
function fmtInt(v){
  if(v === null || v === undefined || v === "") return "—";
  return Number(v).toLocaleString("en-US");
}
function debounce(fn, wait){
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), wait); };
}
function mean(arr){ return arr.reduce((s,v)=>s+v,0) / arr.length; }
function pstdev(arr){
  const m = mean(arr);
  return Math.sqrt(mean(arr.map(v => (v-m)*(v-m))));
}

Chart.defaults.font.family = "'IBM Plex Mono', monospace";
Chart.defaults.color = "#8B92A0";
Chart.defaults.borderColor = "#262B36";

/* ============================================================
   MASTER COUNTRY UNIVERSE (184 countries — the Q7 currency
   screen population, the most complete cross-checked set)
   with a composite Safe Score derived from Q9b's four stress
   dimensions, min–max scaled to a clean -4 … +4 range.
   ============================================================ */
let MASTER = new Map();      // country_name -> {region, score|null}
let ALL_COUNTRIES = [];      // sorted names, length 184
let REGIONS = [];            // 7 regions

function buildMaster(){
  const q7 = DATA.Q7;
  const q9bMap = new Map(DATA.Q9b.map(r => [r.country_name, r]));
  const scored = [];

  q7.forEach(r => {
    const q9 = q9bMap.get(r.country_name);
    if(q9){
      const gdp = q9.gdp_usd_billions || 1;
      const rv = q9.reserves_usd_billions;
      const resPctGdp = (typeof rv === "number" && !Number.isNaN(rv)) ? (rv / gdp * 100) : 0;
      scored.push({
        name: r.country_name, region: r.region,
        debt: q9.debt_pct_gdp, fiscal: q9.fiscal_balance_pct_gdp,
        ca: q9.ca_pct_gdp, res: resPctGdp
      });
    } else {
      MASTER.set(r.country_name, { region: r.region, score: null });
    }
  });

  const zOf = (arr) => { const m = mean(arr), sd = pstdev(arr); return arr.map(v => sd > 0 ? (v-m)/sd : 0); };
  const zd = zOf(scored.map(x => x.debt));
  const zf = zOf(scored.map(x => x.fiscal));
  const zc = zOf(scored.map(x => x.ca));
  const zr = zOf(scored.map(x => x.res));
  const raw = scored.map((x,i) => -zd[i] + zf[i] + zc[i] + zr[i]);
  const minR = Math.min(...raw), maxR = Math.max(...raw);

  scored.forEach((x,i) => {
    const scaled = (minR === maxR) ? 0 : (-4 + (raw[i]-minR) * 8 / (maxR-minR));
    MASTER.set(x.name, { region: x.region, score: Math.round(scaled*10)/10 });
  });

  ALL_COUNTRIES = [...MASTER.keys()].sort();
  REGIONS = [...new Set(ALL_COUNTRIES.map(n => MASTER.get(n).region))].sort();
}

/* ---------- filter state ---------- */
const STATE = {
  regions: new Set(),
  countries: new Set(),
  scoreMin: -4, scoreMax: 4,
  year: "all"
};

function resetState(){
  STATE.regions = new Set(REGIONS);
  STATE.countries = new Set();
  STATE.scoreMin = -4; STATE.scoreMax = 4;
  STATE.year = "all";
}

function countryPasses(name){
  if(STATE.countries.size > 0) return STATE.countries.has(name);
  const info = MASTER.get(name);
  if(!info) return false; // outside the 184-country reference universe
  if(!STATE.regions.has(info.region)) return false;
  if(info.score !== null && (info.score < STATE.scoreMin || info.score > STATE.scoreMax)) return false;
  return true;
}
/** Which regions are currently "in view" — used to show/hide bubbles on the
 *  pre-aggregated Q9a regional chart without ever recomputing its SQL values.
 *  If specific countries are selected, only their region(s) are in view. */
function activeDisplayRegions(){
  if(STATE.countries.size > 0){
    return new Set([...STATE.countries].map(c => MASTER.get(c)?.region).filter(Boolean));
  }
  return STATE.regions;
}
function yearPasses(row, field){
  if(STATE.year === "all") return true;
  if(row[field] === undefined || row[field] === null) return true; // dataset has no year dimension for this row
  return String(row[field]) === String(STATE.year);
}
/** Filters a dataset to the 184-country universe + active region/country/score
 *  selection, and optionally a year field for the 5 dated screens. */
function filterRows(rows, yearField){
  return rows.filter(r => countryPasses(r.country_name) && (!yearField || yearPasses(r, yearField)));
}

function buildYearOptions(){
  const fields = [["Q2","reer_year"],["Q4","stock_data_year"],["Q6","fiscal_year"],["Q7","market_rate_year"],["Q10","latest_year"]];
  const years = new Set();
  fields.forEach(([k,f]) => DATA[k].forEach(r => { if(r[f] !== undefined && r[f] !== null) years.add(r[f]); }));
  return [...years].sort((a,b) => a-b);
}

/* ============================================================
   FILTER CONSOLE
   ============================================================ */
function initFilterConsole(){
  resetState();

  // region multi-select dropdown
  const regionSelect = document.getElementById("regionSelect");
  const regionBtn = document.getElementById("regionSelectBtn");
  const regionPanel = document.getElementById("regionSelectPanel");
  const regionAllCheckbox = document.getElementById("regionAllCheckbox");
  const regionOptionsList = document.getElementById("regionOptionsList");

  regionOptionsList.innerHTML = REGIONS.map(r => `
    <label class="region-option">
      <input type="checkbox" data-region="${r}" checked>${r}
    </label>
  `).join("");
  const regionCheckboxes = [...regionOptionsList.querySelectorAll('input[type="checkbox"]')];

  function updateRegionButtonLabel(){
    const n = STATE.regions.size;
    if(n === REGIONS.length) regionBtn.textContent = "All regions";
    else if(n === 0) regionBtn.textContent = "No regions";
    else if(n === 1) regionBtn.textContent = [...STATE.regions][0];
    else regionBtn.textContent = `${n} regions selected`;
  }
  function updateRegionAllCheckbox(){
    regionAllCheckbox.checked = STATE.regions.size === REGIONS.length;
    regionAllCheckbox.indeterminate = STATE.regions.size > 0 && STATE.regions.size < REGIONS.length;
  }
  updateRegionButtonLabel();
  updateRegionAllCheckbox();

  regionBtn.addEventListener("click", () => {
    if(STATE.countries.size > 0) return; // country selection is in control
    regionSelect.classList.toggle("open");
  });
  document.addEventListener("click", (e) => {
    if(!e.target.closest("#regionSelect")) regionSelect.classList.remove("open");
  });

  regionCheckboxes.forEach(cb => {
    cb.addEventListener("change", () => {
      const r = cb.dataset.region;
      if(cb.checked) STATE.regions.add(r); else STATE.regions.delete(r);
      updateRegionButtonLabel();
      updateRegionAllCheckbox();
      renderAll();
    });
  });
  regionAllCheckbox.addEventListener("change", () => {
    if(regionAllCheckbox.checked){
      STATE.regions = new Set(REGIONS);
      regionCheckboxes.forEach(cb => cb.checked = true);
    } else {
      STATE.regions = new Set();
      regionCheckboxes.forEach(cb => cb.checked = false);
    }
    regionAllCheckbox.indeterminate = false;
    updateRegionButtonLabel();
    renderAll();
  });

  function syncRegionSelectToCountryState(){
    const disabled = STATE.countries.size > 0;
    regionSelect.classList.toggle("disabled", disabled);
    if(disabled) regionSelect.classList.remove("open");
  }

  // country combobox
  const input = document.getElementById("countryInput");
  const suggest = document.getElementById("countrySuggestions");
  const chipsEl = document.getElementById("countryChips");

  function drawCountryChips(){
    chipsEl.innerHTML = [...STATE.countries].map(c => `<span class="country-chip">${c}<button type="button" data-remove="${c}" aria-label="Remove ${c}">×</button></span>`).join("");
    chipsEl.querySelectorAll("button[data-remove]").forEach(b => {
      b.addEventListener("click", () => {
        STATE.countries.delete(b.dataset.remove);
        drawCountryChips();
        syncRegionSelectToCountryState();
        renderAll();
      });
    });
  }
  input.addEventListener("input", () => {
    const q = input.value.trim().toLowerCase();
    if(!q){ suggest.classList.remove("open"); suggest.innerHTML = ""; return; }
    const matches = ALL_COUNTRIES.filter(n => n.toLowerCase().includes(q) && !STATE.countries.has(n)).slice(0,8);
    suggest.innerHTML = matches.map(n => `<div class="suggestion" data-name="${n}">${n}</div>`).join("") || `<div class="suggestion suggestion-empty">No match</div>`;
    suggest.classList.add("open");
  });
  suggest.addEventListener("click", (e) => {
    const item = e.target.closest(".suggestion[data-name]");
    if(!item) return;
    STATE.countries.add(item.dataset.name);
    input.value = "";
    suggest.classList.remove("open"); suggest.innerHTML = "";
    drawCountryChips();
    syncRegionSelectToCountryState();
    renderAll();
  });
  document.addEventListener("click", (e) => {
    if(!e.target.closest(".country-combo")){ suggest.classList.remove("open"); }
  });

  // score slider (dual thumb)
  const minInput = document.getElementById("scoreMin");
  const maxInput = document.getElementById("scoreMax");
  const fill = document.getElementById("scoreFill");
  const minLabel = document.getElementById("scoreMinLabel");
  const maxLabel = document.getElementById("scoreMaxLabel");

  function drawSlider(){
    const lo = Math.min(Number(minInput.value), Number(maxInput.value));
    const hi = Math.max(Number(minInput.value), Number(maxInput.value));
    STATE.scoreMin = lo; STATE.scoreMax = hi;
    const pct = (v) => ((v - (-4)) / 8) * 100;
    fill.style.left = pct(lo) + "%";
    fill.style.right = (100 - pct(hi)) + "%";
    minLabel.textContent = (lo >= 0 ? "+" : "") + lo.toFixed(1);
    maxLabel.textContent = (hi >= 0 ? "+" : "") + hi.toFixed(1);
  }
  const debouncedRender = debounce(renderAll, 90);
  [minInput, maxInput].forEach(inp => inp.addEventListener("input", () => { drawSlider(); debouncedRender(); }));
  drawSlider();

  // year select
  const yearSelect = document.getElementById("yearSelect");
  const years = buildYearOptions();
  yearSelect.innerHTML = `<option value="all">All years</option>` + years.map(y => `<option value="${y}">${y}</option>`).join("");
  yearSelect.addEventListener("change", () => { STATE.year = yearSelect.value; renderAll(); });

  // reset
  document.getElementById("filterReset").addEventListener("click", () => {
    resetState();
    regionCheckboxes.forEach(cb => cb.checked = true);
    updateRegionButtonLabel();
    updateRegionAllCheckbox();
    syncRegionSelectToCountryState();
    STATE.countries.clear(); drawCountryChips();
    minInput.value = -4; maxInput.value = 4; drawSlider();
    yearSelect.value = "all";
    renderAll();
  });
}

function updateFilterCount(){
  const n = ALL_COUNTRIES.filter(countryPasses).length;
  document.getElementById("filterCount").textContent = `${n} of ${ALL_COUNTRIES.length} countries`;
}

/* ---------- generic sortable / searchable table controller ---------- */
function createTable(elId, columns){
  const el = document.getElementById(elId);
  const search = document.querySelector(`.table-search[data-table="${elId}"]`);
  let allRows = [];
  let sortKey = null, sortDir = 1;

  function currentData(){
    let data = allRows;
    if(search && search.value){
      const q = search.value.toLowerCase();
      data = data.filter(r => Object.values(r).some(v => String(v ?? "").toLowerCase().includes(q)));
    }
    if(sortKey){
      data = [...data].sort((a,b) => {
        let av = a[sortKey], bv = b[sortKey];
        const an = Number(av), bn = Number(bv);
        if(!Number.isNaN(an) && !Number.isNaN(bn) && av !== null && bv !== null && av !== "" && bv !== ""){
          return (an - bn) * sortDir;
        }
        return String(av ?? "").localeCompare(String(bv ?? "")) * sortDir;
      });
    }
    return data;
  }

  function draw(){
    const data = currentData();
    const thead = "<thead><tr>" + columns.map(c =>
      `<th data-key="${c.key}" class="${sortKey===c.key ? 'sorted' : ''}">${c.label}</th>`).join("") + "</tr></thead>";

    let tbody;
    if(data.length === 0){
      tbody = `<tbody><tr class="empty-row"><td colspan="${columns.length}">No countries match the current filters.</td></tr></tbody>`;
    } else {
      tbody = "<tbody>" + data.map(row => {
        const flagCol = columns.find(c => c.flag);
        const cls = flagCol ? "flag-" + flagClass(row[flagCol.key]) : "";
        const tds = columns.map(c => {
          let val = row[c.key];
          let content;
          if(c.flag){
            content = val ? `<span class="pill ${flagClass(val)}">${flagLabel(val)}</span>` : "—";
          } else if(c.number){
            content = fmtNum(val, c.decimals ?? 1);
          } else if(c.int){
            content = fmtInt(val);
          } else {
            content = (val === null || val === undefined || val === "") ? "—" : val;
          }
          return `<td class="${c.name ? "name-cell" : ""}">${content}</td>`;
        }).join("");
        return `<tr class="${cls}">${tds}</tr>`;
      }).join("") + "</tbody>";
    }
    el.innerHTML = thead + tbody;

    el.querySelectorAll("thead th").forEach(th => {
      th.addEventListener("click", () => {
        const key = th.dataset.key;
        sortDir = (sortKey === key) ? -sortDir : 1;
        sortKey = key;
        draw();
      });
    });
  }

  if(search && !search.dataset.bound){
    search.dataset.bound = "1";
    search.addEventListener("input", draw);
  }

  return { update(rows){ allRows = rows; draw(); } };
}

/* ---------- chart registry: destroy + rebuild on every filter change ---------- */
const CHARTS = {};
function setChart(canvasId, config){
  const ctx = document.getElementById(canvasId);
  if(!ctx) return;
  if(CHARTS[canvasId]) CHARTS[canvasId].destroy();
  CHARTS[canvasId] = new Chart(ctx, config);
}

/* ============================================================
   KPI STRIP  (recomputed from the filtered universe)
   ============================================================ */
function renderKPIs(){
  const q9b = filterRows(DATA.Q9b);
  const nActive = ALL_COUNTRIES.filter(countryPasses).length;

  const redCountries = q9b.filter(r => r.country_stress_score >= 3).length;
  const activeRegions = STATE.countries.size > 0 ? "custom selection" : `${STATE.regions.size} of ${REGIONS.length} regions`;

  // Safest / riskiest by composite Safe Score, among countries currently in view.
  // The Safe Score is built from Q9b — a current cross-section, not a time series —
  // so this reflects the most recent data available rather than a specific year.
  const scoredActive = ALL_COUNTRIES
    .filter(countryPasses)
    .map(name => ({ name, score: MASTER.get(name).score }))
    .filter(x => x.score !== null);
  const safest = scoredActive.length ? scoredActive.reduce((a,b) => b.score > a.score ? b : a) : null;
  const riskiest = scoredActive.length ? scoredActive.reduce((a,b) => b.score < a.score ? b : a) : null;

  const kpis = [
    {label:"Countries in view", value: nActive, sub: activeRegions, cls:""},
    {label:"3+ dimension stress", value: redCountries, sub:"debt · reserves · fiscal · CA simultaneously", cls:"red"},
    {label:"Safest country", value: safest ? safest.name : "—", sub: safest ? `Safe score ${fmtNum(safest.score,1)} · most recent data` : "No countries match filters", cls:"green", small:true},
    {label:"Riskiest country", value: riskiest ? riskiest.name : "—", sub: riskiest ? `Safe score ${fmtNum(riskiest.score,1)} · most recent data` : "No countries match filters", cls:"red", small:true},
  ];

  document.getElementById("kpiRow").innerHTML = kpis.map(k => `
    <div class="kpi">
      <div class="kpi-label">${k.label}</div>
      <div class="kpi-value ${k.cls}" style="${k.small ? 'font-size:22px' : ''}">${k.value}</div>
      <div class="kpi-sub">${k.sub}</div>
    </div>
  `).join("");
}

/* ============================================================
   Q9a — regional bubble chart (UNFILTERED aggregate) + Q9b table (filtered)
   ============================================================ */
const tblQ9b = createTable("tblQ9b", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"income_group", label:"Income group"},
  {key:"debt_pct_gdp", label:"Debt % GDP", number:true},
  {key:"reserves_usd_billions", label:"Reserves $bn", number:true, decimals:2},
  {key:"fiscal_balance_pct_gdp", label:"Fiscal bal. % GDP", number:true},
  {key:"ca_pct_gdp", label:"CA % GDP", number:true},
  {key:"country_stress_score", label:"Stress score", int:true},
]);

function renderQ9(){
  const ctx = document.getElementById("chartQ9a");
  const activeRegions = activeDisplayRegions();
  // Values are always the true, unrecomputed SQL aggregates — filters only
  // decide which regions' bubbles are shown, never how a bubble's own
  // stress score/GDP share is calculated.
  const rows = DATA.Q9a.filter(r => activeRegions.has(r.region));
  try{
    setChart("chartQ9a", {
      type:"bubble",
      data:{ datasets:[{
        label:"Regions",
        data: rows.map(r => ({
          x: r.pct_regional_gdp_in_stressed_countries,
          y: r.avg_regional_stress_score,
          r: Math.max(6, Math.sqrt(r.total_regional_gdp_usd_billions)/6),
          region: r.region, flag: r.regional_stress_flag
        })),
        backgroundColor: rows.map(r => COLORS[flagClass(r.regional_stress_flag)] + "cc"),
        borderColor: rows.map(r => COLORS[flagClass(r.regional_stress_flag)]),
        borderWidth:1.5
      }]},
      options:{
        plugins:{
          legend:{display:false},
          tooltip:{callbacks:{label:(ctx)=>{
            const d = ctx.raw;
            return `${d.region}: stress ${d.y.toFixed(2)}, ${d.x.toFixed(0)}% GDP exposed`;
          }}}
        },
        scales:{
          x:{title:{display:true,text:"% regional GDP in stressed countries"}, grid:{color:"#1B1F28"}},
          y:{title:{display:true,text:"Avg. regional stress score"}, grid:{color:"#1B1F28"}}
        }
      }
    });
  } catch(err){ console.error("[dashboard] Q9a chart failed:", err); }

  tblQ9b.update(filterRows(DATA.Q9b));
}

/* ============================================================
   Q1 — reserves vs debt bubble + table
   ============================================================ */
const tblQ1 = createTable("tblQ1", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"debt_pct_gdp", label:"Debt % GDP", number:true},
  {key:"reserves_now_usd_billions", label:"Reserves $bn", number:true, decimals:2},
  {key:"reserve_change_6mo_usd_billions", label:"Δ 6mo $bn", number:true, decimals:2},
  {key:"reserves_pct_of_debt", label:"Reserves % debt", number:true, decimals:2},
  {key:"months_import_cover", label:"Import cover (mo)", number:true},
  {key:"liquidity_risk_flag", label:"Flag", flag:true},
]);

function renderQ1(){
  const rows = filterRows(DATA.Q1);
  try{
    setChart("chartQ1", {
      type:"bubble",
      data:{ datasets:[{
        data: rows.map(r => ({
          x:r.debt_pct_gdp, y:r.reserves_pct_of_debt,
          r: Math.max(5, Math.sqrt(r.gdp_usd_billions)/12),
          name:r.country_name
        })),
        backgroundColor: rows.map(r => COLORS[flagClass(r.liquidity_risk_flag)] + "cc"),
        borderColor: rows.map(r => COLORS[flagClass(r.liquidity_risk_flag)]),
        borderWidth:1.5
      }]},
      options:{
        plugins:{legend:{display:false}, tooltip:{callbacks:{label:(ctx)=>{
          const d = ctx.raw; return `${d.name}: debt ${d.x.toFixed(0)}% GDP, reserves ${d.y.toFixed(1)}% of debt`;
        }}}},
        scales:{
          x:{title:{display:true,text:"Debt (% of GDP)"}, grid:{color:"#1B1F28"}},
          y:{title:{display:true,text:"Reserves (% of debt)"}, grid:{color:"#1B1F28"}}
        }
      }
    });
  } catch(err){ console.error("[dashboard] Q1 chart failed:", err); }

  tblQ1.update(rows);
}

/* ============================================================
   Q8 — doomsday clock table
   ============================================================ */
const tblQ8 = createTable("tblQ8", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"income_group", label:"Income group"},
  {key:"debt_cagr_pct", label:"Debt CAGR %", number:true, decimals:2},
  {key:"gdp_cagr_pct", label:"GDP CAGR %", number:true, decimals:2},
  {key:"excess_debt_growth_pct", label:"Excess growth %", number:true, decimals:2},
  {key:"years_to_ratio_doubling", label:"Years to doubling", number:true, decimals:1},
  {key:"doomsday_urgency_flag", label:"Flag", flag:true},
]);
function renderQ8(){ tblQ8.update(filterRows(DATA.Q8)); }

/* ============================================================
   Q2 — devaluation risk table (year: reer_year)
   ============================================================ */
const tblQ2 = createTable("tblQ2", [
  {key:"country_name", label:"Country", name:true},
  {key:"country_code", label:"ISO"},
  {key:"reer_year", label:"Year", int:true},
  {key:"reer_index", label:"REER index", number:true, decimals:2},
  {key:"current_account_pct_gdp_now", label:"CA % GDP (now)", number:true, decimals:2},
  {key:"ca_pct_deterioration_2yr", label:"CA deteriorat. 2y", number:true, decimals:2},
  {key:"ca_pct_gdp_forecast_2yr_ahead", label:"CA fcst +2y", number:true, decimals:2},
  {key:"ca_pct_gdp_forecast_4yr_ahead", label:"CA fcst +4y", number:true, decimals:2},
  {key:"devaluation_risk_flag", label:"Flag", flag:true},
]);
function renderQ2(){ tblQ2.update(filterRows(DATA.Q2, "reer_year")); }

/* ============================================================
   Q3 — compare cards (IDA vs IBRD) — UNFILTERED, lending-category aggregate
   ============================================================ */
function renderQ3(){
  const rows = DATA.Q3;
  const el = document.getElementById("q3Cards");
  el.innerHTML = rows.map(r => `
    <div class="compare-card">
      <h4>${r.lending_category}</h4>
      <div class="sub">${r.num_countries} countries · ${r.num_country_year_observations} country-year obs.</div>
      <div class="compare-stat"><span class="k">Avg YoY export price change</span><span class="v">${fmtNum(r.avg_yoy_export_price_pct_change,2)}%</span></div>
      <div class="compare-stat"><span class="k">Volatility (σ)</span><span class="v">${fmtNum(r.export_price_volatility_stddev,2)}</span></div>
      <div class="compare-stat"><span class="k">Worst YoY shock</span><span class="v">${fmtNum(r.worst_export_price_yoy_shock,2)}%</span></div>
      <div class="compare-stat"><span class="k">Best YoY swing</span><span class="v">${fmtNum(r.best_export_price_yoy_swing,2)}%</span></div>
    </div>
  `).join("");
}

/* ============================================================
   Q7 — PPP mispricing chart + table (year: market_rate_year)
   ============================================================ */
const tblQ7 = createTable("tblQ7", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"market_rate_year", label:"Year", int:true},
  {key:"ppp_implied_rate", label:"PPP rate", number:true, decimals:2},
  {key:"actual_market_rate", label:"Market rate", number:true, decimals:2},
  {key:"pct_over_undervalued", label:"% over/under", number:true, decimals:2},
  {key:"valuation_flag", label:"Flag", flag:true},
]);
function renderQ7(){
  const rows = filterRows(DATA.Q7, "market_rate_year");
  const top15 = [...rows].sort((a,b)=> Math.abs(b.pct_over_undervalued) - Math.abs(a.pct_over_undervalued)).slice(0,15);

  try{
    setChart("chartQ7", {
      type:"bar",
      data:{
        labels: top15.map(r => r.country_name),
        datasets:[{
          data: top15.map(r => r.pct_over_undervalued),
          backgroundColor: top15.map(r => COLORS[flagClass(r.valuation_flag)]),
        }]
      },
      options:{
        indexAxis:"y",
        plugins:{legend:{display:false}},
        scales:{ x:{title:{display:true, text:"% over/undervalued vs PPP"}, grid:{color:"#1B1F28"}}, y:{grid:{display:false}} }
      }
    });
  } catch(err){ console.error("[dashboard] Q7 chart failed:", err); }

  tblQ7.update(rows);
}

/* ============================================================
   Q4 — market disconnect table (year: stock_data_year)
   ============================================================ */
const tblQ4 = createTable("tblQ4", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"income_group", label:"Income group"},
  {key:"stock_data_year", label:"Year", int:true},
  {key:"stock_3yr_gain_pct", label:"Stock 3yr gain %", number:true, decimals:1},
  {key:"fiscal_balance_now_pct_gdp", label:"Fiscal bal. now", number:true, decimals:2},
  {key:"fiscal_balance_deterioration", label:"Fiscal deterior.", number:true, decimals:2},
  {key:"market_mispricing_flag", label:"Flag", flag:true},
]);
function renderQ4(){ tblQ4.update(filterRows(DATA.Q4, "stock_data_year")); }

/* ============================================================
   Q6 — spending efficiency scatter + table (year: fiscal_year)
   ============================================================ */
const tblQ6 = createTable("tblQ6", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"fiscal_year", label:"Year", int:true},
  {key:"govt_spend_pct_gdp", label:"Spend % GDP", number:true, decimals:2},
  {key:"gdp_growth_pct", label:"GDP growth %", number:true, decimals:2},
  {key:"usd_growth_per_usd_spend", label:"$growth/$spend", number:true, decimals:4},
  {key:"spending_efficiency_flag", label:"Flag", flag:true},
]);
function renderQ6(){
  const rows = filterRows(DATA.Q6, "fiscal_year");
  try{
    setChart("chartQ6", {
      type:"scatter",
      data:{ datasets:[{
        data: rows.map(r => ({x:r.govt_spend_pct_gdp, y:r.usd_growth_per_usd_spend, name:r.country_name})),
        backgroundColor: rows.map(r => COLORS[flagClass(r.spending_efficiency_flag)]),
        pointRadius:5, pointHoverRadius:7
      }]},
      options:{
        plugins:{legend:{display:false}, tooltip:{callbacks:{label:(ctx)=>{
          const d = ctx.raw; return `${d.name}: spend ${d.x.toFixed(1)}% GDP, ${d.y.toFixed(3)} $growth/$spend`;
        }}}},
        scales:{
          x:{title:{display:true,text:"Govt. spend (% of GDP)"}, grid:{color:"#1B1F28"}},
          y:{title:{display:true,text:"USD GDP growth per USD spend"}, grid:{color:"#1B1F28"}}
        }
      }
    });
  } catch(err){ console.error("[dashboard] Q6 chart failed:", err); }

  tblQ6.update(rows);
}

/* ============================================================
   Q5 — misery index chart + table
   ============================================================ */
const tblQ5 = createTable("tblQ5", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"unemployment_rate_pct", label:"Unemployment %", number:true, decimals:2},
  {key:"inflation_pct", label:"Inflation %", number:true, decimals:2},
  {key:"misery_index", label:"Misery index", number:true, decimals:2},
  {key:"global_misery_rank", label:"Global rank", int:true},
  {key:"regional_misery_rank", label:"Regional rank", int:true},
  {key:"misery_severity_flag", label:"Flag", flag:true},
]);
function renderQ5(){
  const rows = filterRows(DATA.Q5);
  const top15 = [...rows].sort((a,b)=> b.misery_index - a.misery_index).slice(0,15);

  try{
    setChart("chartQ5", {
      type:"bar",
      data:{
        labels: top15.map(r => r.country_name),
        datasets:[{ data: top15.map(r => r.misery_index), backgroundColor: top15.map(r => COLORS[flagClass(r.misery_severity_flag)]) }]
      },
      options:{
        indexAxis:"y",
        plugins:{legend:{display:false}},
        scales:{ x:{title:{display:true,text:"Misery index (unemployment % + inflation %)"}, grid:{color:"#1B1F28"}}, y:{grid:{display:false}} }
      }
    });
  } catch(err){ console.error("[dashboard] Q5 chart failed:", err); }

  tblQ5.update(rows);
}

/* ============================================================
   Q10 — deterioration streak table (year: latest_year)
   ============================================================ */
const tblQ10 = createTable("tblQ10", [
  {key:"country_name", label:"Country", name:true},
  {key:"region", label:"Region"},
  {key:"income_group", label:"Income group"},
  {key:"latest_year", label:"Year", int:true},
  {key:"fiscal_deterioration_streak_yrs", label:"Fiscal streak (yr)", int:true},
  {key:"debt_deterioration_streak_yrs", label:"Debt streak (yr)", int:true},
  {key:"ca_deterioration_streak_yrs", label:"CA streak (yr)", int:true},
  {key:"latest_fiscal_balance_pct_gdp", label:"Latest fiscal %", number:true, decimals:2},
  {key:"latest_debt_pct_gdp", label:"Latest debt %", number:true, decimals:2},
  {key:"structural_decline_flag", label:"Flag", flag:true},
]);
function renderQ10(){ tblQ10.update(filterRows(DATA.Q10, "latest_year")); }

/* ============================================================
   STATIC "full screen" counts — computed once from the
   184-country universe (not affected by live filters)
   ============================================================ */
function renderUniverseCounts(){
  const within = (rows) => rows.filter(r => MASTER.has(r.country_name)).length;
  const set = (id, n, noun) => { const el = document.getElementById(id); if(el) el.textContent = `Full screen — ${n} ${noun}`; };
  set("countQ1", within(DATA.Q1), "highest-debt economies");
  set("countQ7", within(DATA.Q7), "currencies");
  set("countQ5", within(DATA.Q5), "countries");
}

/* ============================================================
   SIDEBAR COLLAPSE/EXPAND
   ============================================================ */
function initSidebarToggle(){
  const sidebar = document.getElementById("sidebar");
  const btn = document.getElementById("sidebarToggle");
  if(!sidebar || !btn) return;

  function applyState(collapsed){
    sidebar.classList.toggle("collapsed", collapsed);
    btn.textContent = collapsed ? "›" : "‹";
    btn.setAttribute("aria-label", collapsed ? "Expand sidebar" : "Collapse sidebar");
    btn.title = collapsed ? "Expand sidebar" : "Collapse sidebar";
  }

  let stored = null;
  try{ stored = localStorage.getItem("gsr-sidebar-collapsed"); } catch(e){}
  applyState(stored === "1");

  btn.addEventListener("click", () => {
    const collapsed = !sidebar.classList.contains("collapsed");
    applyState(collapsed);
    try{ localStorage.setItem("gsr-sidebar-collapsed", collapsed ? "1" : "0"); } catch(e){}
  });
}

/* ============================================================
   BOOT
   ============================================================ */
function safe(name, fn){
  try{ fn(); }
  catch(err){ console.error(`[dashboard] ${name} failed:`, err); }
}

function renderAll(){
  safe("renderKPIs", renderKPIs);
  safe("renderQ9", renderQ9);
  safe("renderQ1", renderQ1);
  safe("renderQ8", renderQ8);
  safe("renderQ2", renderQ2);
  safe("renderQ7", renderQ7);
  safe("renderQ4", renderQ4);
  safe("renderQ6", renderQ6);
  safe("renderQ5", renderQ5);
  safe("renderQ10", renderQ10);
  updateFilterCount();
}

document.addEventListener("DOMContentLoaded", () => {
  if(typeof Chart === "undefined"){
    console.error("[dashboard] Chart.js did not load — check js/vendor/chart.min.js is present. Charts will be skipped; tables will still render.");
  }
  if(typeof Papa === "undefined"){
    showLoadError(new Error("Papa Parse did not load — check js/vendor/papaparse.min.js is present."));
    return;
  }
  initSidebarToggle();

  loadAllData()
    .then((data) => {
      DATA = data;
      hideLoadingOverlay();
      buildMaster();
      initFilterConsole();
      renderUniverseCounts();
      safe("renderQ3", renderQ3); // unfiltered, render once
      renderAll();
    })
    .catch((err) => {
      showLoadError(err);
    });
});

function hideLoadingOverlay(){
  const el = document.getElementById("loadingOverlay");
  if(el) el.remove();
}
function showLoadError(err){
  console.error("[dashboard] Failed to load data:", err);
  hideLoadingOverlay();
  const banner = document.getElementById("loadErrorBanner");
  const detail = document.getElementById("loadErrorDetail");
  if(detail) detail.textContent = err && err.message ? err.message : String(err);
  if(banner) banner.hidden = false;
}
