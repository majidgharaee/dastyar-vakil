window.addEventListener('load',()=>setTimeout(async()=>{
  const result={status:'PASS',checks:[]};
  const check=(condition,label)=>{result.checks.push({label,pass:!!condition});if(!condition)result.status='FAIL';};
  const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
  try{
    showPage('profile');
    document.querySelector('#officePinToggle').click();
    document.querySelector('#officePinNew').value='1234';
    document.querySelector('#officePinConfirm').value='1234';
    document.querySelector('#saveOfficePin').click();
    await wait(1200);
    check(state.officeSecurity.pinEnabled===true,'first PIN enrollment succeeds');
    check(state.officeSecurity.pinVersion===2&&state.officeSecurity.pinIterations===210000,'PIN uses versioned PBKDF2 policy');
    const originalHash=state.officeSecurity.pinHash;

    document.querySelector('#officePinNew').value='9876';
    document.querySelector('#officePinConfirm').value='9876';
    document.querySelector('#saveOfficePin').click();
    await wait(30);
    check(document.querySelector('#sensitiveAuthDialog').open,'PIN replacement requests fresh authentication');
    check(state.officeSecurity.pinHash===originalHash,'PIN hash unchanged before authentication');
    cancelSensitiveAction();

    document.querySelector('#deleteAccount').click();
    document.querySelector('#deleteAccountPhrase').value='حذف حساب';
    document.querySelector('#deleteAccountPhrase').dispatchEvent(new Event('input',{bubbles:true}));
    document.querySelector('#deleteAccountDialog').close('confirm');
    await wait(30);
    check(document.querySelector('#sensitiveAuthDialog').open,'delete-all requests fresh authentication');
    check(state.officeSecurity.pinEnabled===true,'phrase alone does not delete protected state');
    document.querySelector('#sensitiveAuthPin').value='1234';
    document.querySelector('#sensitiveAuthPinForm').requestSubmit();
    await wait(1500);
    check(state.officeSecurity.pinEnabled===false&&state.userProfile.name==='', 'correct current PIN authorizes deletion');
  }catch(error){result.status='FAIL';result.error=String(error.stack||error);}
  document.body.innerHTML=`<pre id="securityQaResult">${JSON.stringify(result)}</pre>`;
},350));
