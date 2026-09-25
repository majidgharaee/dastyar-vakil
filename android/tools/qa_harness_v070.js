window.addEventListener('load',()=>setTimeout(async()=>{
  const result={status:'PASS',checks:[]};
  const check=(condition,label)=>{result.checks.push({label,pass:!!condition});if(!condition)result.status='FAIL';};
  const click=selector=>document.querySelector(selector)?.click();
  try{
    check((window.qaErrors||[]).length===0,'no startup JavaScript errors');
    click('[data-page-link="addresses"]');
    check(document.querySelectorAll('#addressCategorySummary [data-address-category]').length===3,'three curated address category tiles');
    click('#addressCategorySummary [data-address-category]');
    check(document.querySelector('[data-page="address-category"]').classList.contains('active'),'address category detail opens');
    check(document.querySelectorAll('#essentialPlaceList .pdf-place').length>0,'curated addresses render');
    check(!document.querySelector('#essentialPlaceList').innerText.includes('صفحه'),'raw OCR page metadata hidden');

    click('[data-nav="library"]'); click('[data-filter="unity"]');
    check(document.querySelectorAll('#unityYearGrid .unity-year-card').length===10,'ten unity year cards');
    check(!document.querySelector('#unityYearGrid').innerText.includes('۱٬۴۰۵'),'year formatting has no thousands separator');
    click('[data-nav="library"]'); click('[data-filter="opinion"]');
    check(document.querySelectorAll('#opinionYearGrid .unity-year-card').length===10,'ten opinion year cards');
    check(document.querySelectorAll('#opinionYearGrid .unity-year-card:disabled').length>=1,'missing opinion years are explicitly disabled');

    click('[data-nav="calculators"]');
    check(document.querySelectorAll('#calculatorGrid .calculator-card').length===17,'seventeen calculators visible immediately');
    check(document.querySelectorAll('#calculatorGrid .calc-status').length===17,'calculator evidence labels visible');
    click('[data-calculator="late"]');
    document.querySelector('input[name="amount"]').value='1000000';
    document.querySelector('select[name="dueYear"]').value='1403'; document.querySelector('select[name="dueMonth"]').value='فروردین';
    document.querySelector('select[name="payYear"]').value='1404'; document.querySelector('select[name="payMonth"]').value='فروردین';
    document.querySelector('#activeCalculatorForm').requestSubmit();
    check(document.querySelector('#calculatorResult').innerText.includes('شاخص پرداخت'),'inflation calculator works');

    click('[data-nav="assistant"]');
    check(document.querySelector('[data-page="assistant"]').innerText.includes('موتور قاعده‌محور آفلاین'),'assistant limitation disclosed');
    click('[data-nav="about"]');
    const about=document.querySelector('[data-page="about"]').innerText;
    check(about.includes('دفتر وکالت دکتر مجید قرایی')&&about.includes('۰۹۱۲۱۵۴۳۹۹۴'),'creator and contact shown');
  }catch(error){result.status='FAIL';result.error=String(error.stack||error);}
  result.startupErrors=window.qaErrors||[];
  document.body.innerHTML=`<pre id="qaResult">${JSON.stringify(result)}</pre>`;
},300));
