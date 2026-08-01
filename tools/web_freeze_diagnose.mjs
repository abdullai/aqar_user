// تشخيص تجمّد Flutter Web — يجمع أخطاء Console من Chrome تلقائياً.
// التشغيل: node tools/web_freeze_diagnose.mjs http://127.0.0.1:8765

import { chromium } from '../fal_backend/node_modules/playwright/index.mjs';

const baseUrl = process.argv[2] || 'http://127.0.0.1:8765';
const routes = ['/', '/#/userDashboard', '/#/userdashboard'];

const errors = [];
const logs = [];

function push(kind, text) {
  const line = `[${kind}] ${text}`;
  logs.push(line);
  if (kind === 'error' || kind === 'pageerror') errors.push(line);
}

async function probe(page, url) {
  console.log('\n=== Probe:', url, '===');
  errors.length = 0;

  page.removeAllListeners('console');
  page.removeAllListeners('pageerror');

  page.on('console', (msg) => {
    const t = msg.type();
    const text = msg.text();
    if (t === 'error' || text.includes('AqarWebError') || text.includes('Null check')) {
      push(t, text);
    }
  });
  page.on('pageerror', (err) => push('pageerror', String(err)));

  const started = Date.now();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 });
  } catch (e) {
    push('error', `goto failed: ${e}`);
    return { url, errors: [...errors], ms: Date.now() - started };
  }

  // انتظر تحميل Flutter
  await page.waitForTimeout(12000);

  const hash = await page.evaluate(() => location.hash);
  const title = await page.title();

  // محاولة نقر (شريط سفلي / زر)
  let clickOk = false;
  try {
    const navBtn = page.locator('flt-glass-pane').first();
    await page.mouse.click(40, page.viewportSize().height - 30);
    clickOk = true;
  } catch (_) {}

  await page.waitForTimeout(2000);

  const bodyText = await page.evaluate(() => document.body?.innerText?.slice(0, 500) || '');

  console.log('  hash:', hash);
  console.log('  title:', title);
  console.log('  body preview:', bodyText.replace(/\s+/g, ' ').slice(0, 120));
  console.log('  errors:', errors.length);
  for (const e of errors.slice(0, 8)) console.log('   ', e);

  return { url, hash, errors: [...errors], clickOk, ms: Date.now() - started };
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 390, height: 844 },
  locale: 'ar-SA',
});
const page = await context.newPage();

const results = [];
for (const route of routes) {
  const full = baseUrl.replace(/\/$/, '') + (route.startsWith('/') ? route : `/${route}`);
  results.push(await probe(page, full));
}

await browser.close();

console.log('\n========== SUMMARY ==========');
for (const r of results) {
  console.log(`${r.url} | hash=${r.hash} | errors=${r.errors.length} | ${r.ms}ms`);
}
if (results.every((r) => r.errors.length === 0)) {
  console.log('No console errors captured (UI freeze may still occur from main-thread block).');
} else {
  process.exitCode = 1;
}
