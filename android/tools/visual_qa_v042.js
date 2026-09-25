'use strict';

const { chromium } = require('playwright');
const { pathToFileURL } = require('url');
const path = require('path');

(async () => {
  const root = path.resolve(__dirname, '..');
  const out = path.join(root, 'manual-build-v42');
  const browser = await chromium.launch({
    headless: true,
    executablePath: 'C:\\Program Files (x86)\\Microsoft\\EdgeCore\\153.0.4234.32\\msedge.exe',
  });
  const page = await browser.newPage({ viewport: { width: 498, height: 1080 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(pathToFileURL(path.join(root, 'app', 'src', 'main', 'assets', 'index.html')).href);
  await page.waitForSelector('.page[data-page="home"].active');

  const initialStaticCount = await page.locator('.page[data-page="calculators"] #calculatorGrid .calculator-card').count();
  if (initialStaticCount !== 17) throw new Error(`Before interaction expected 17 calculator cards, got ${initialStaticCount}`);
  const serviceText = await page.locator('.page[data-page="home"]').innerText();
  for (const label of ['سفارش لایحه و دادخواست', 'سفارش تایپ فوری', 'هوش مصنوعی حقوقی', 'چک‌لیست دعاوی', 'همکاری وکلا', 'نشانی‌ها و مراجع']) {
    if (!serviceText.includes(label)) throw new Error(`Missing home service label: ${label}`);
  }
  const navLabels = await page.locator('.bottom-nav small').allTextContents();
  const expectedLabels = ['کتابخانه', 'هوش مصنوعی', 'محاسبات', 'دستیار وکیل', 'درباره ما'];
  if (JSON.stringify(navLabels) !== JSON.stringify(expectedLabels)) throw new Error(`Wrong nav labels: ${navLabels.join(' | ')}`);
  await page.screenshot({ path: path.join(out, '01-home-v042.png'), fullPage: true });

  // Critical regression test: enter the page and inspect cards without touching search.
  await page.click('[data-nav="calculators"]');
  await page.waitForSelector('.page[data-page="calculators"].active');
  const calculatorCount = await page.locator('#calculatorGrid .calculator-card:visible').count();
  if (calculatorCount !== 17) throw new Error(`Immediately after entry expected 17 visible cards, got ${calculatorCount}`);
  const query = await page.locator('#calculatorSearch').inputValue();
  if (query !== '') throw new Error(`Calculator search was not reset: ${query}`);
  await page.screenshot({ path: path.join(out, '02-calculators-immediate-v042.png'), fullPage: true });

  await page.click('[data-calculator="date"]');
  await page.fill('input[name="baseDate"]', '2026-09-21');
  await page.fill('input[name="days"]', '22');
  await page.selectOption('select[name="direction"]', 'add');
  await page.click('#activeCalculatorForm button[type="submit"]');
  await page.waitForSelector('.date-result');
  const isoResult = (await page.locator('.date-result code').textContent()).trim();
  if (isoResult !== '2026-10-13') throw new Error(`Unexpected date result: ${isoResult}`);
  await page.screenshot({ path: path.join(out, '03-date-calculation-v042.png'), fullPage: true });

  await page.click('[data-nav="about"]');
  await page.waitForSelector('.page[data-page="about"].active');
  const about = await page.locator('.page[data-page="about"]').innerText();
  if (!about.includes('دفتر وکالت دکتر مجید قرایی') || !about.includes('۰۹۱۲۱۵۴۳۹۹۴')) throw new Error('About/contact details missing');
  await page.screenshot({ path: path.join(out, '04-about-v042.png'), fullPage: true });

  if (errors.length) throw new Error(`Page errors: ${errors.join(' | ')}`);
  console.log(JSON.stringify({ status: 'PASS', initialStaticCount, calculatorCount, searchUntouched: true, navLabels, isoResult,
    screenshots: ['01-home-v042.png', '02-calculators-immediate-v042.png', '03-date-calculation-v042.png', '04-about-v042.png'] }, null, 2));
  await browser.close();
})().catch(error => { console.error(error.stack || error.message); process.exit(1); });
