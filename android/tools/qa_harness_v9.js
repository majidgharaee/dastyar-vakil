(() => {
  const tests = [];
  const check = (name, condition, detail = '') => tests.push({ name, pass: !!condition, detail });
  try {
    check('No special-service banner', !document.querySelector('.feature-banner'));
    check('Horizontal services present', !!document.querySelector('.service-carousel'));
    check('Exactly 100 civil checklists', education.filter(x => x.kind === 'civil').length === 100);
    check('Exactly 100 criminal checklists', education.filter(x => x.kind === 'criminal').length === 100);
    check('Exactly 200 checklist briefs', resources.filter(x => x.type === 'pleading' && x.id.startsWith('pleading-checklist-')).length === 200);
    check('Unity coverage begins in 1370', resources.some(x => x.type === 'unity' && unityYear(x) === '1370'));
    check('Unity archive expanded', resources.filter(x => x.type === 'unity').length >= 300);
    check('Opinion index retained', resources.filter(x => x.type === 'opinion').length >= 2300);
    check('Year index spans 1370-1405', legalIndexYears.length === 36 && legalIndexYears.at(-1) === '1370');
    check('Seventeen calculators visible', calculators.length === 17);
    renderLibrary('law', '');
    check('Twenty-four law category cards', document.querySelectorAll('.law-category-card').length === 24);
    const civil = laws.find(x => normalizeSearch(x.title).includes('قانون مدنی'));
    check('Civil code available', !!civil);
    if (civil) {
      openDocument(civil.id);
      check('Law opens as structured sections', document.querySelectorAll('.law-section').length >= 3);
    }
    runSearch('ماده ۲۲۰');
    check('Global search returns legal results', document.querySelectorAll('#searchResultList .list-item').length > 0);
    check('AI provider settings exist', ['openrouterModel','groqModel','huggingfaceModel','aiMode','aiConsent'].every(id => document.getElementById(id)));
    check('No JavaScript errors', (window.qaErrors || []).length === 0, (window.qaErrors || []).join(' | '));
  } catch (error) {
    check('Harness execution', false, error.stack || String(error));
  }
  const passed = tests.filter(x => x.pass).length;
  document.body.innerHTML = `<main style="font-family:Tahoma;direction:rtl;padding:24px"><h1 id="qaResult">${passed === tests.length ? 'PASS' : 'FAIL'} ${passed}/${tests.length}</h1>${tests.map(x => `<p style="color:${x.pass ? 'green' : 'red'}">${x.pass ? '✓' : '✗'} ${x.name}${x.detail ? ` — ${x.detail}` : ''}</p>`).join('')}</main>`;
  window.QA_RESULTS = tests;
})();
