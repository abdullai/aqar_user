/**
 * Builds a compact city-level snapshot from REGA open-data CSVs
 * (civillizard/Saudi-Real-Estate-Data). Do not ship the 160MB zip into the app.
 *
 * Usage:
 *   node tool/build_rega_open_indicators.js <extracted-quarterlies-dir> <out.json>
 */
const fs = require('fs');
const path = require('path');

function walk(dir, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p, acc);
    else if (name.toLowerCase().endsWith('.csv')) acc.push(p);
  }
  return acc;
}

function parseCsv(text) {
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/).filter((l) => l.trim());
  if (lines.length < 2) return [];
  const headers = lines[0].split(',').map((h) => h.trim());
  return lines.slice(1).map((line) => {
    const cols = line.split(',');
    const row = {};
    headers.forEach((h, i) => {
      row[h] = (cols[i] ?? '').trim();
    });
    return row;
  });
}

function num(v) {
  if (v == null) return null;
  const t = String(v).replace(/,/g, '').replace(/٬/g, '').trim();
  if (!t || t.toUpperCase() === 'NULL' || t === '-') return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

function pick(row, keys) {
  for (const k of keys) {
    if (row[k] != null && String(row[k]).trim() !== '') return String(row[k]).trim();
  }
  const names = Object.keys(row);
  for (const want of keys) {
    const hit = names.find((n) => n.replace(/\s+/g, '') === want.replace(/\s+/g, ''));
    if (hit && String(row[hit]).trim() !== '') return String(row[hit]).trim();
  }
  return '';
}

const root = process.argv[2];
const outFile = process.argv[3];
if (!root || !outFile) {
  console.error('usage: node tool/build_rega_open_indicators.js <quarterlies-dir> <out.json>');
  process.exit(1);
}

const files = walk(root);
const SALES_Q = process.env.REGA_SALES_Q || '2026-1'; // year-quarter
const RENTAL_Q = process.env.REGA_RENTAL_Q || '2026-1';
const qRegex = (yq) => {
  const [y, q] = yq.split('-');
  const ord = { 1: '1st', 2: '2nd', 3: '3rd', 4: '4th' }[q];
  return new RegExp(`(Q${q}-${y}|${ord}-?Q-?${y})`, 'i');
};
const salesFiles = files.filter((f) => /sales/i.test(f) && qRegex(SALES_Q).test(path.basename(f)));
const rentalFiles = files.filter((f) => /rental/i.test(f) && qRegex(RENTAL_Q).test(path.basename(f)));

const sales = [];
for (const f of salesFiles) {
  for (const row of parseCsv(fs.readFileSync(f, 'utf8'))) {
    const city = pick(row, ['المدينة', 'city']);
    const type = pick(row, ['النوع', 'نوع العقار']);
    const klass = pick(row, ['الاستخدام', 'تصنيف العقار']);
    const deals = num(pick(row, ['عدد الصفقات']));
    const avgM2 = num(pick(row, ['متوسط سعر المتر ر.س', 'متوسط سعر المتر']));
    if (!city || !type || !deals || deals <= 0 || avgM2 == null || avgM2 <= 0) continue;
    sales.push({
      region: pick(row, ['المنطقة']),
      city,
      type,
      klass,
      deals,
      avg_m2: Math.round(avgM2 * 100) / 100,
    });
  }
}

const rentAcc = new Map();
for (const f of rentalFiles) {
  for (const row of parseCsv(fs.readFileSync(f, 'utf8'))) {
    const city = pick(row, ['المدينة']);
    const type = pick(row, ['نوع العقار']);
    const klass = pick(row, ['تصنيف العقار']);
    const deals = num(pick(row, ['عدد الصفقات'])) ?? 0;
    const avgRent = num(pick(row, ['متوسط الايجار', 'متوسط الإيجار']));
    const avgM2 = num(pick(row, ['متوسط الايجار لكل متر مربع', 'متوسط الإيجار لكل متر مربع']));
    if (!city || !type || deals <= 0 || avgRent == null || avgRent <= 0) continue;
    const key = [pick(row, ['المنطقة']), city, type, klass].join('\t');
    const cur = rentAcc.get(key) || {
      region: pick(row, ['المنطقة']),
      city,
      type,
      klass,
      deals: 0,
      rentSum: 0,
      m2Sum: 0,
      m2Deals: 0,
    };
    cur.deals += deals;
    cur.rentSum += avgRent * deals;
    if (avgM2 != null && avgM2 > 0) {
      cur.m2Sum += avgM2 * deals;
      cur.m2Deals += deals;
    }
    rentAcc.set(key, cur);
  }
}

const rentals = [...rentAcc.values()].map((r) => ({
  region: r.region,
  city: r.city,
  type: r.type,
  klass: r.klass,
  deals: r.deals,
  avg_rent: Math.round(r.rentSum / r.deals),
  avg_m2: r.m2Deals > 0 ? Math.round((r.m2Sum / r.m2Deals) * 100) / 100 : null,
}));

const payload = {
  source: 'REGA open indicators (MOJ/REGA via Saudi National Open Data)',
  attribution: 'civillizard/Saudi-Real-Estate-Data — KSA Open Data License',
  sales_period: { year: Number(SALES_Q.split('-')[0]), quarter: Number(SALES_Q.split('-')[1]) },
  rental_period: { year: Number(RENTAL_Q.split('-')[0]), quarter: Number(RENTAL_Q.split('-')[1]) },
  sales,
  rentals,
};

fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, JSON.stringify(payload));
console.log(
  `wrote ${outFile} sales=${sales.length} rentals=${rentals.length} bytes=${fs.statSync(outFile).size}`,
);
