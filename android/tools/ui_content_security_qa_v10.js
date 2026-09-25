'use strict';
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const assets = path.join(root, 'app', 'src', 'main', 'assets');
const out = path.join(root, 'qa-v10');
fs.mkdirSync(out, {recursive:true});

const b64 = name => fs.existsSync(path.join(assets,name)) ? fs.readFileSync(path.join(assets,name)).toString('base64') : Buffer.from('[]').toString('base64');
let html = fs.readFileSync(path.join(assets,'index.html'),'utf8')
  .replace('<link rel="stylesheet" href="styles.css">', `<style>${fs.readFileSync(path.join(assets,'styles.css'),'utf8')}</style>`)
  .replace('__LEGAL_DATA_B64__', b64('legal-data.json'))
  .replace('__ADDRESS_DATA_B64__', b64('address-data.json'))
  .replace('__INFLATION_DATA_B64__', b64('inflation-data.json'))
  .replace('__INHERITANCE_DATA_B64__', b64('inheritance-data.json'));

const mock = `
window.qaStore={clients:JSON.stringify([{id:'kept',name:'موکل محفوظ'}])};const qaStore=window.qaStore;
window.LawyerApp={
 secureGet:k=>qaStore[k]||'',securePut:(k,v)=>(qaStore[k]=v,true),
 getLegalCatalogStats:()=>JSON.stringify({authorities:2,categories:2,catalog_only:2,unverified:2,rag_eligible:0,last_synced_at:'1'}),
 getLegalCatalogCategories:()=>JSON.stringify([{id:'civil',code:'civil',name:'حقوق مدنی',count:1},{id:'criminal',code:'criminal',name:'حقوق کیفری',count:1}]),
 queryLegalCatalog:(category,query)=>JSON.stringify([{id:'law-1',title:'قانون آزمایشی کاتالوگ',type_label:'قانون',content_status:'catalog_only',verification_status:'unverified',effect_status:'unknown',has_text:false,has_full_text:false,rag_eligible:false,official_verified:false,category_review_status:'pending_qa',category_verified:false}].filter(x=>(!category||category==='civil')&&(!query||x.title.includes(query)))),
 getLegalCatalogItem:id=>JSON.stringify({id,title:'قانون آزمایشی کاتالوگ',type_label:'قانون',content_status:'catalog_only',verification_status:'unverified',effect_status:'unknown',has_text:false,has_full_text:false,rag_eligible:false,official_verified:false,category_review_status:'pending_qa',category_verified:false}),
 refreshLegalCatalog:()=>{},
 getDirectoryStats:()=>JSON.stringify({entities:2,groups:2,subgroups:2,needs_verification:1,last_synced_at:'1'}),
 getDirectoryGroups:()=>JSON.stringify([{code:'courts',name:'مراجع قضایی',count:1},{code:'professional',name:'مراجع حرفه‌ای',count:1}]),
 getDirectorySubgroups:()=>JSON.stringify([]),
 queryDirectory:(group,subgroup,query)=>JSON.stringify([{id:'dir-1',name:'دادگاه آزمایشی',address:'تهران، نشانی آزمایشی',city:'تهران',phone:'02100000000',group_code:'courts',group_name:'مراجع قضایی',subgroup_name:'دادگاه',verification_status:'needs_verification',confidence_level:'low',verification_required:true,official_verified:false,source_url:'',map_url:''}].filter(x=>(!group||group==='courts')&&(!query||x.name.includes(query)))),
 getDirectoryItem:()=>'',refreshDirectory:()=>{},canScheduleExactReminders:()=>true,hasAiCredential:()=>false
};`;
html = html.replace('<script src="app.js" defer></script>', '');

(async()=>{
 const exe=process.env.QA_EDGE_PATH||'C:\\Program Files (x86)\\Microsoft\\EdgeCore\\153.0.4234.48\\msedge.exe';
 const browser=await chromium.launch({headless:true,executablePath:exe});
 const page=await browser.newPage({viewport:{width:498,height:1080},deviceScaleFactor:1});
 const errors=[]; page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://app.local/',route=>route.fulfill({status:200,contentType:'text/html; charset=utf-8',body:html}));
 await page.goto('https://app.local/',{waitUntil:'load'});
 await page.addScriptTag({content:mock});
 await page.addScriptTag({content:fs.readFileSync(path.join(assets,'app.js'),'utf8')});
 await page.waitForTimeout(500);
 if(errors.length)throw new Error('Startup JavaScript: '+errors.join(' | '));
 const results=[]; const check=(name,ok,detail='')=>results.push({name,pass:!!ok,detail});
 const legacyLegal=JSON.parse(fs.readFileSync(path.join(assets,'legal-data.json'),'utf8'));
 check('v9 full-law fallback preserved',legacyLegal.filter(x=>x.type==='law').length===25);
 check('v9 unity archive preserved',legacyLegal.filter(x=>x.type==='unity').length===305);
 check('v9 opinion index preserved',legacyLegal.filter(x=>x.type==='opinion').length===2323);
 check('User local data preserved',(await page.evaluate(()=>JSON.parse(window.qaStore.clients).some(x=>x.id==='kept'))));
 await page.locator('[data-nav="library"]').first().evaluate(el=>el.click()); await page.locator('[data-filter="law"]').evaluate(el=>el.click());
 check('Cloud legal categories shown',(await page.locator('[data-law-category-id]').count())===2);
 await page.locator('[data-law-category-id="civil"]').evaluate(el=>el.click());
 const lawText=await page.locator('#libraryList').innerText();
 check('catalog_only visible',lawText.includes('catalog_only'));
 check('unverified visible',lawText.includes('unverified'));
 check('rag ineligible visible',lawText.includes('غیرمجاز برای استناد AI'));
 await page.locator('[data-open-catalog-document="law-1"]').evaluate(el=>el.click());
 check('AI prohibition in detail',(await page.locator('#documentView').innerText()).includes('برای استناد هوش مصنوعی مجاز نیست'));
 await page.locator('[data-page-link="addresses"]').first().evaluate(el=>el.click());
 check('Cloud directory groups shown',(await page.locator('[data-address-category]').count())===2);
 await page.locator('[data-address-category="courts"]').evaluate(el=>el.click());
 const addressText=await page.locator('#essentialPlaceList').innerText();
 check('Directory entry shown',addressText.includes('دادگاه آزمایشی'));
 check('Directory verification warning shown',addressText.includes('نیازمند راستی‌آزمایی'));
 check('AI prompt enforces rag rule',fs.readFileSync(path.join(assets,'app.js'),'utf8').includes('rag_eligible=false'));
 check('No JavaScript errors',errors.length===0,errors.join(' | '));
 await page.screenshot({path:path.join(out,'v10-directory-and-catalog.png'),fullPage:true});
 fs.writeFileSync(path.join(out,'ui-content-security-results.json'),JSON.stringify({passed:results.filter(x=>x.pass).length,total:results.length,results},null,2));
 await browser.close();
 if(results.some(x=>!x.pass)){console.error(results);process.exit(1);} console.log(`PASS ${results.length}/${results.length}`);
})().catch(e=>{console.error(e);process.exit(1);});
