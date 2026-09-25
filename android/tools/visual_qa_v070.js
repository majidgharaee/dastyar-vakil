'use strict';

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const root = path.resolve(__dirname, '..');
  const assets = path.join(root, 'app', 'src', 'main', 'assets');
  const out = path.join(root, 'qa-v070');
  fs.mkdirSync(out, {recursive:true});
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
  await page.screenshot({path:path.join(out,'01-home-v070.png'),fullPage:true});

  await page.click('[data-nav="calculators"]');
  const calculators=await page.locator('#calculatorGrid .calculator-card:visible').count();
  if(calculators!==17) throw new Error(`Calculator count ${calculators}`);
  await page.screenshot({path:path.join(out,'02-calculators-v070.png'),fullPage:true});
  await page.click('[data-calculator="late"]');
  await page.fill('input[name="amount"]','1000000');
  await page.selectOption('select[name="dueYear"]','1403'); await page.selectOption('select[name="dueMonth"]','فروردین');
  await page.selectOption('select[name="payYear"]','1404'); await page.selectOption('select[name="payMonth"]','فروردین');
  await page.click('#activeCalculatorForm button[type="submit"]');
  if(!(await page.locator('#calculatorResult').innerText()).includes('شاخص پرداخت')) throw new Error('Inflation result missing');

  await page.click('[data-page-link="addresses"]');
  const addressCategories=await page.locator('#addressCategorySummary [data-address-category]').count();
  if(addressCategories!==3) throw new Error(`Curated address category count ${addressCategories}`);
  await page.locator('#addressCategorySummary [data-address-category]').first().click();
  const addressItems=await page.locator('#essentialPlaceList .pdf-place').count();
  if(addressItems<1) throw new Error('Curated address category opened empty');
  const addressText=await page.locator('#essentialPlaceList').innerText();
  if(addressText.includes('مورد ۱')||addressText.includes('صفحه NaN')) throw new Error('Unverified OCR address leaked into UI');
  await page.screenshot({path:path.join(out,'03-addresses-v070.png'),fullPage:true});

  await page.click('[data-nav="library"]'); await page.click('[data-filter="unity"]');
  const unityYears=await page.locator('#unityYearGrid .unity-year-card').count();
  if(unityYears!==10) throw new Error(`Unity years ${unityYears}`);
  if((await page.locator('#unityYearGrid').innerText()).includes('۱٬۴۰۵')) throw new Error('Grouped Persian year remains');
  await page.screenshot({path:path.join(out,'04-unity-years-v070.png'),fullPage:true});
  await page.click('[data-nav="library"]'); await page.click('[data-filter="opinion"]');
  const opinionYears=await page.locator('#opinionYearGrid .unity-year-card').count();
  if(opinionYears!==10) throw new Error(`Opinion years ${opinionYears}`);
  const disabledOpinionYears=await page.locator('#opinionYearGrid .unity-year-card:disabled').count();
  if(disabledOpinionYears<1) throw new Error('Missing-year disclosure is not visible');
  await page.screenshot({path:path.join(out,'05-opinion-years-v070.png'),fullPage:true});

  await page.click('[data-nav="assistant"]');
  const assistantText=await page.locator('[data-page="assistant"]').innerText();
  if(!assistantText.includes('موتور قاعده‌محور آفلاین')) throw new Error('Assistant capability disclosure missing');
  await page.screenshot({path:path.join(out,'06-assistant-v070.png'),fullPage:true});
  await page.click('[data-nav="about"]');
  const about=await page.locator('[data-page="about"]').innerText();
  if(!about.includes('دفتر وکالت دکتر مجید قرایی')||!about.includes('۰۹۱۲۱۵۴۳۹۹۴')) throw new Error('Creator/contact content missing');
  await page.screenshot({path:path.join(out,'07-about-v070.png'),fullPage:true});

  if(errors.length) throw new Error(`Page errors: ${errors.join(' | ')}`);
  console.log(JSON.stringify({status:'PASS',calculators,addressCategories,addressItems,unityYears,opinionYears,disabledOpinionYears,screenshots:7},null,2));
  await browser.close();
})().catch(error=>{console.error(error.stack||error.message);process.exit(1);});
