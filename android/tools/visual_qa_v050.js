'use strict';

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const root = path.resolve(__dirname, '..');
  const assets = path.join(root, 'app', 'src', 'main', 'assets');
  const out = path.join(root, 'manual-build-v50');
  let html = fs.readFileSync(path.join(assets, 'index.html'), 'utf8');
  const css = fs.readFileSync(path.join(assets, 'styles.css'), 'utf8');
  const js = fs.readFileSync(path.join(assets, 'app.js'), 'utf8');
  const legal = fs.readFileSync(path.join(assets, 'legal-data.json')).toString('base64');
  const addresses = fs.readFileSync(path.join(assets, 'address-data.json')).toString('base64');
  html = html.replace('<link rel="stylesheet" href="styles.css">', `<style>${css}</style>`)
    .replace('__LEGAL_DATA_B64__', legal).replace('__ADDRESS_DATA_B64__', addresses)
    .replace('<script src="app.js" defer></script>', `<script>${js}</script>`);

  const browser = await chromium.launch({headless:true,executablePath:'C:\\Program Files (x86)\\Microsoft\\EdgeCore\\153.0.4234.32\\msedge.exe'});
  const page = await browser.newPage({viewport:{width:498,height:1080},deviceScaleFactor:1});
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await page.setContent(html,{waitUntil:'load'});
  await page.waitForSelector('.page[data-page="home"].active');
  const homeText=await page.locator('[data-page="home"]').innerText();
  if(homeText.includes('وقت‌ها و هشدارها')) throw new Error('Home still contains hearing shortcut');
  await page.screenshot({path:path.join(out,'01-home-v050.png'),fullPage:true});

  await page.click('[data-filter="unity"]'); await page.waitForSelector('[data-page="unity"].active');
  const yearCards=await page.locator('.unity-year-card').count(); if(yearCards<2) throw new Error(`Expected year cards, got ${yearCards}`);
  await page.screenshot({path:path.join(out,'02-unity-years-v050.png'),fullPage:true});

  await page.click('[data-page-link="education"]');
  await page.click('[data-education-filter="civil"]'); const civil=await page.locator('#educationList .education-card').count();
  await page.click('[data-education-filter="criminal"]'); const criminal=await page.locator('#educationList .education-card').count();
  if(civil<50||criminal<50) throw new Error(`Checklist counts ${civil}/${criminal}`);

  await page.click('[data-page-link="addresses"]'); await page.waitForSelector('[data-page="addresses"].active');
  const categoryCount=await page.locator('#addressCategory option').count(); if(categoryCount<10) throw new Error(`Only ${categoryCount} address groups`);
  const shownAddresses=await page.locator('#essentialPlaceList .pdf-place').count(); if(shownAddresses!==80) throw new Error(`Expected lazy first 80 addresses, got ${shownAddresses}`);
  await page.screenshot({path:path.join(out,'03-addresses-v050.png'),fullPage:true});

  await page.click('[data-nav="assistant"]'); await page.fill('#assistantInput','برای مطالبه وجه چه مدارکی لازم است؟'); await page.click('#assistantForm button[type="submit"]');
  await page.waitForTimeout(250); const aiText=await page.locator('#chatMessages .legal-answer').last().innerText();
  for(const heading of ['صورت مسئله','ارکان و نقاط اثبات','مدارک و اقدامات اثباتی','صلاحیت و مرجع','مواعد و فوریت','اقدام بعدی پیشنهادی']) if(!aiText.includes(heading)) throw new Error(`AI response missing ${heading}`);
  await page.screenshot({path:path.join(out,'04-legal-ai-v050.png'),fullPage:true});

  await page.click('[data-nav="calculators"]'); const calculators=await page.locator('#calculatorGrid .calculator-card:visible').count(); if(calculators!==17) throw new Error(`Calculator count ${calculators}`);
  if(errors.length) throw new Error(`Page errors: ${errors.join(' | ')}`);
  console.log(JSON.stringify({status:'PASS',yearCards,civil,criminal,categoryCount,shownAddresses,calculators},null,2));
  await browser.close();
})().catch(error=>{console.error(error.stack||error.message);process.exit(1);});
