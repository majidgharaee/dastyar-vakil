'use strict';

const { chromium } = require('playwright');
const { pathToFileURL } = require('url');
const path = require('path');

(async () => {
  const root = path.resolve(__dirname, '..');
  const browser = await chromium.launch({
    headless: true,
    executablePath: 'C:\\Program Files (x86)\\Microsoft\\EdgeCore\\153.0.4234.32\\msedge.exe',
  });
  const page = await browser.newPage({ viewport: { width: 498, height: 1080 }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(pathToFileURL(path.join(root, 'app', 'src', 'main', 'assets', 'index.html')).href);
  await page.waitForSelector('.page[data-page="home"].active');
  await page.screenshot({ path: path.join(root, 'manual-build-v41', '01-home.png'), fullPage: true });

  await page.click('[data-nav="calculators"]');
  await page.waitForSelector('.page[data-page="calculators"].active');
  const calculatorCount = await page.locator('#calculatorGrid .calculator-card').count();
  if (calculatorCount !== 17) throw new Error(`Expected 17 visible cards, got ${calculatorCount}`);
  const dateCardVisible = await page.locator('[data-calculator="date"]').isVisible();
  if (!dateCardVisible) throw new Error('Date calculator card is not visible');
  await page.screenshot({ path: path.join(root, 'manual-build-v41', '02-calculators-all.png'), fullPage: true });

  await page.click('[data-calculator="date"]');
  await page.fill('input[name="baseDate"]', '2026-09-21');
  await page.fill('input[name="days"]', '22');
  await page.selectOption('select[name="direction"]', 'add');
  await page.click('#activeCalculatorForm button[type="submit"]');
  await page.waitForSelector('.date-result');
  const isoResult = await page.locator('.date-result code').textContent();
  if (isoResult.trim() !== '2026-10-13') throw new Error(`Unexpected date result: ${isoResult}`);
  await page.screenshot({ path: path.join(root, 'manual-build-v41', '03-date-calculation.png'), fullPage: true });

  await page.click('#aboutButton');
  await page.waitForSelector('.page[data-page="about"].active');
  const aboutText = await page.locator('.page[data-page="about"]').innerText();
  if (!aboutText.includes('دفتر وکالت دکتر مجید قرایی') || !aboutText.includes('۰۹۱۲۱۵۴۳۹۹۴')) throw new Error('About/contact details missing');
  await page.screenshot({ path: path.join(root, 'manual-build-v41', '04-about-us.png'), fullPage: true });

  const firstBack = await page.evaluate(() => window.handleNativeBack());
  const secondBack = await page.evaluate(() => window.handleNativeBack());
  if (firstBack !== 'home' || secondBack !== 'exit') throw new Error(`Back contract failed: ${firstBack}, ${secondBack}`);
  if (errors.length) throw new Error(`Page errors: ${errors.join(' | ')}`);

  console.log(JSON.stringify({ status: 'PASS', calculatorCount, dateCardVisible, isoResult: isoResult.trim(), backContract: [firstBack, secondBack], screenshots: ['01-home.png', '02-calculators-all.png', '03-date-calculation.png', '04-about-us.png'] }, null, 2));
  await browser.close();
})().catch(error => {
  console.error(error.stack || error.message);
  process.exit(1);
});
