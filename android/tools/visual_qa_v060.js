'use strict';

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const root = path.resolve(__dirname, '..');
  const assets = path.join(root, 'app', 'src', 'main', 'assets');
  const out = path.join(root, 'manual-build-v60');
  let html = fs.readFileSync(path.join(assets, 'index.html'), 'utf8');
  const css = fs.readFileSync(path.join(assets, 'styles.css'), 'utf8');
  const js = fs.readFileSync(path.join(assets, 'app.js'), 'utf8');
  for (const [marker,file] of [['__LEGAL_DATA_B64__','legal-data.json'],['__ADDRESS_DATA_B64__','address-data.json'],['__INFLATION_DATA_B64__','inflation-data.json'],['__INHERITANCE_DATA_B64__','inheritance-data.json']]) {
    html = html.replace(marker, fs.readFileSync(path.join(assets,file)).toString('base64'));
  }
  html = html.replace('<link rel="stylesheet" href="styles.css">', `<style>${css}</style>`)
    .replace('<script src="app.js" defer></script>', `<script>${js}</script>`);

  const browser = await chromium.launch({headless:true,executablePath:'C:\\Program Files (x86)\\Microsoft\\EdgeCore\\153.0.4234.32\\msedge.exe'});
  const page = await browser.newPage({viewport:{width:498,height:1080},deviceScaleFactor:1});
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await page.setContent(html,{waitUntil:'load'});
  await page.waitForSelector('.page[data-page="home"].active');

  await page.click('[data-page-link="addresses"]');
  const addressCategories=await page.locator('#addressCategorySummary [data-address-category]').count();
  if(addressCategories!==14) throw new Error(`Address category count ${addressCategories}`);
  if((await page.locator('[data-page="addresses"]').innerText()).includes('هشدار اعتبار نشانی')) throw new Error('Address warning still exists');
  await page.screenshot({path:path.join(out,'01-address-categories-v060.png'),fullPage:true});
  await page.locator('#addressCategorySummary [data-address-category]').first().click();
  await page.waitForSelector('[data-page="address-category"].active');
  const addressItems=await page.locator('#essentialPlaceList .pdf-place').count();
  if(addressItems<1) throw new Error('Address category opened empty');
  await page.screenshot({path:path.join(out,'02-address-list-v060.png'),fullPage:true});

  await page.click('[data-nav="library"]');
  if(await page.locator('.library-audit').count()) throw new Error('Library audit cards still exist');
  if((await page.locator('[data-page="library"]').innerText()).includes('به‌روزرسانی محتوای آفلاین')) throw new Error('Offline update card still exists');
  await page.click('[data-filter="unity"]');
  const unityYears=await page.locator('#unityYearGrid .unity-year-card').count(); if(unityYears!==10) throw new Error(`Unity years ${unityYears}`);
  await page.screenshot({path:path.join(out,'03-unity-years-v060.png'),fullPage:true});
  await page.click('[data-nav="library"]'); await page.click('[data-filter="opinion"]');
  const opinionYears=await page.locator('#opinionYearGrid .unity-year-card').count(); if(opinionYears!==10) throw new Error(`Opinion years ${opinionYears}`);
  await page.screenshot({path:path.join(out,'04-opinion-years-v060.png'),fullPage:true});

  await page.click('[data-nav="assistant"]');
  if(await page.locator('#chatMessages .legal-answer').count()) throw new Error('AI intro card still exists');

  await page.click('[data-nav="calculators"]');
  const calculators=await page.locator('#calculatorGrid .calculator-card:visible').count(); if(calculators!==17) throw new Error(`Calculator count ${calculators}`);
  await page.click('[data-calculator="late"]');
  await page.fill('input[name="amount"]','1000000');
  await page.selectOption('select[name="dueYear"]','1403'); await page.selectOption('select[name="dueMonth"]','فروردین');
  await page.selectOption('select[name="payYear"]','1404'); await page.selectOption('select[name="payMonth"]','فروردین');
  await page.click('#activeCalculatorForm button[type="submit"]');
  if(!(await page.locator('#calculatorResult').innerText()).includes('شاخص پرداخت')) throw new Error('Inflation result missing');
  await page.screenshot({path:path.join(out,'05-inflation-calculator-v060.png'),fullPage:true});
  await page.click('[data-page-link="calculators"]'); await page.click('[data-calculator="inheritance"]');
  await page.fill('input[name="amount"]','1200000000'); await page.fill('input[name="sons"]','1'); await page.fill('input[name="daughters"]','1');
  await page.check('input[name="father"]'); await page.check('input[name="mother"]');
  await page.click('#activeCalculatorForm button[type="submit"]');
  if(!(await page.locator('#calculatorResult').innerText()).includes('سهم هر پسر')) throw new Error('Inheritance result missing');
  await page.screenshot({path:path.join(out,'06-inheritance-calculator-v060.png'),fullPage:true});

  await page.click('[data-page-link="profile"]');
  const profileText=await page.locator('[data-page="profile"]').innerText();
  if(profileText.includes('درباره ما و ارتباط با سازنده')||profileText.includes('درخواست حذف اطلاعات ارسالی')) throw new Error('Removed profile cards remain');
  await page.click('[data-page-link="about"]');
  if((await page.locator('[data-page="about"]').innerText()).includes('درباره محتوای حقوقی')) throw new Error('About content card remains');
  if(errors.length) throw new Error(`Page errors: ${errors.join(' | ')}`);
  console.log(JSON.stringify({status:'PASS',addressCategories,addressItems,unityYears,opinionYears,calculators},null,2));
  await browser.close();
})().catch(error=>{console.error(error.stack||error.message);process.exit(1);});
