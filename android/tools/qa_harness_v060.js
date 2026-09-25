window.addEventListener('load',()=>setTimeout(()=>{
  const result={status:'PASS',checks:[]};
  const check=(condition,label)=>{result.checks.push({label,pass:!!condition});if(!condition)result.status='FAIL';};
  const click=selector=>document.querySelector(selector)?.click();
  try{
    check((window.qaErrors||[]).length===0,'no startup JavaScript errors');
    result.debug={addresses:typeof pdfAddressCatalog==='undefined'?'undefined':pdfAddressCatalog.length,categories:typeof addressCategories==='undefined'?'undefined':addressCategories.length,resources:typeof resources==='undefined'?'undefined':resources.length};
    click('[data-page-link="addresses"]');
    result.debug.activeAfterAddress=document.querySelector('.page.active')?.dataset.page;
    check(document.querySelectorAll('#addressCategorySummary [data-address-category]').length===14,'14 address category tiles');
    check(!document.querySelector('[data-page="addresses"]').innerText.includes('هشدار اعتبار نشانی'),'address warning removed');
    click('#addressCategorySummary [data-address-category]');
    check(document.querySelector('[data-page="address-category"]').classList.contains('active'),'category detail opens');
    check(document.querySelectorAll('#essentialPlaceList .pdf-place').length>0,'category lists all records');

    click('[data-nav="library"]');
    result.debug.activeAfterLibrary=document.querySelector('.page.active')?.dataset.page;
    check(!document.querySelector('.library-audit'),'library count cards removed');
    check(!document.querySelector('[data-page="library"]').innerText.includes('به‌روزرسانی محتوای آفلاین'),'offline update card removed');
    click('[data-filter="unity"]'); check(document.querySelectorAll('#unityYearGrid .unity-year-card').length===10,'10 unity years');
    click('[data-nav="library"]'); click('[data-filter="opinion"]'); check(document.querySelectorAll('#opinionYearGrid .unity-year-card').length===10,'10 opinion years');

    click('[data-nav="assistant"]'); check(document.querySelectorAll('#chatMessages .legal-answer').length===0,'AI intro rectangle removed');
    click('[data-nav="calculators"]'); check(document.querySelectorAll('#calculatorGrid .calculator-card').length===17,'17 calculators visible');
    result.debug.activeAfterCalculators=document.querySelector('.page.active')?.dataset.page;
    click('[data-calculator="late"]');
    document.querySelector('input[name="amount"]').value='1000000';
    document.querySelector('select[name="dueYear"]').value='1403'; document.querySelector('select[name="dueMonth"]').value='فروردین';
    document.querySelector('select[name="payYear"]').value='1404'; document.querySelector('select[name="payMonth"]').value='فروردین';
    document.querySelector('#activeCalculatorForm').requestSubmit();
    check(document.querySelector('#calculatorResult').innerText.includes('شاخص پرداخت'),'inflation calculator result');
    click('[data-page-link="calculators"]'); click('[data-calculator="inheritance"]');
    document.querySelector('input[name="amount"]').value='1200000000'; document.querySelector('input[name="sons"]').value='1'; document.querySelector('input[name="daughters"]').value='1';
    document.querySelector('input[name="father"]').checked=true; document.querySelector('input[name="mother"]').checked=true;
    document.querySelector('#activeCalculatorForm').requestSubmit();
    check(document.querySelector('#calculatorResult').innerText.includes('سهم هر پسر'),'inheritance calculator result');

    click('[data-page-link="profile"]'); const profile=document.querySelector('[data-page="profile"]').innerText;
    check(!profile.includes('درباره ما و ارتباط با سازنده')&&!profile.includes('درخواست حذف اطلاعات ارسالی'),'profile cards removed');
    click('[data-page-link="about"]'); check(!document.querySelector('[data-page="about"]').innerText.includes('درباره محتوای حقوقی'),'about content card removed');
  }catch(error){result.status='FAIL';result.error=String(error.stack||error);}
  result.startupErrors=window.qaErrors||[];
  document.body.innerHTML=`<pre id="qaResult">${JSON.stringify(result)}</pre>`;
},200));
