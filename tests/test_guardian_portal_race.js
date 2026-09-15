const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('src/kof5_tts/guardian_portal.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const pause = () => new Promise(resolve => setImmediate(resolve));
const pending = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};
const reply = (status, data) => ({
  ok: status >= 200 && status < 300,
  status,
  text: async () => data == null ? '' : JSON.stringify(data),
  json: async () => data,
});

class Element {
  constructor(id = '') { this.id = id; this.value = ''; this.textContent = ''; this.children = []; this.handlers = {}; this.hidden = false; }
  addEventListener(name, handler) { this.handlers[name] = handler; }
  focus() {}
  reportValidity() { return true; }
  replaceChildren() { this.children = []; this.textContent = ''; if (this.id === 'patient') this.value = ''; }
  append(...children) { this.children.push(...children); if (this.id === 'patient' && !this.value) this.value = children[0].value; }
}

async function run() {
  const elements = Object.fromEntries([
    'signin-form', 'signin-button', 'signin-status', 'signin-card', 'email', 'password',
    'signup-button', 'signup-status',
    'portal-card', 'portal-status', 'memory-card', 'memory-form', 'memory-status',
    'links', 'patient', 'facts', 'avoid-facts', 'starter-question', 'starter-hint',
    'category', 'content', 'save-memory', 'cancel-edit', 'logout',
  ].map(id => [id, new Element(id)]));
  const body = { classList: { add() {}, remove() {} } };
  const document = { body, getElementById: id => elements[id], createElement: tag => new Element(tag) };
  const firstA = pending();
  const oldA = pending();
  const firstSave = pending();
  const secondSave = pending();
  const posts = [];
  const patches = [];
  let bMemory = { fact_id: 'B-fact', category: 'travel', content: 'B memory' };
  let aReads = 0;
  let logins = 0;
  let pausedLogin = null;
  const signupOne = pending();
  const signupTwo = pending();
  const signupThree = pending();
  const signups = [];
  const links = ['A', 'B'].map(patient_id => ({ patient_id, relationship: '가상 가족', access_status: 'verified', effective_at: '2020-01-01T00:00:00Z', expires_at: null }));

  async function fetch(url, options = {}) {
    if (url === '/guardian/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/signup')) {
      signups.push({ body: JSON.parse(options.body), headers: options.headers });
      return [signupOne, signupTwo, signupThree][signups.length - 1].promise;
    }
    if (url.includes('/auth/v1/token')) {
      if (pausedLogin) { const slow = pausedLogin; pausedLogin = null; return slow.promise; }
      return reply(200, { access_token: `session-${++logins}`, user: { id: 'guardian' } });
    }
    if (url.includes('/guardian_links')) return reply(200, links);
    if (url.includes('/family_context') && options.method === 'POST') {
      posts.push(JSON.parse(options.body));
      if (posts.length === 1) return firstSave.promise;
      if (posts.length === 2) return secondSave.promise;
      return reply(201, null);
    }
    if (url.includes('/family_context') && options.method === 'PATCH') {
      patches.push({ url, body: JSON.parse(options.body), headers: options.headers });
      if (patches.length === 2) return reply(200, []);
      bMemory = { ...bMemory, ...patches.at(-1).body };
      return reply(200, [bMemory]);
    }
    if (url.includes('patient_id=eq.A')) {
      aReads += 1;
      if (aReads === 1) return firstA.promise;
      if (aReads === 3) return oldA.promise;
      return reply(200, [{ fact_id: 'A-fact', category: 'travel', content: 'A new memory' }]);
    }
    if (url.includes('patient_id=eq.B')) return reply(200, [bMemory]);
    throw new Error(`unexpected URL ${url}`);
  }

  vm.runInNewContext(script, { document, fetch, console });
  await pause();
  const submit = handler => handler({ preventDefault() {} });
  const displayed = () => elements.facts.children.map(card => card.children[1].textContent);

  elements.email.value = 'synthetic@example.invalid';
  elements.password.value = 'synthetic';
  elements.category.value = 'travel';
  const login = submit(elements['signin-form'].handlers.submit);
  await pause();
  elements.content.value = 'A draft';
  elements.patient.value = 'B';
  await elements.patient.handlers.change();
  assert.equal(elements.content.value, '', 'patient switch discards the previous draft');
  assert.deepEqual(displayed(), ['B memory']);
  firstA.resolve(reply(200, [{ fact_id: 'A-fact', category: 'travel', content: 'A memory' }]));
  await login;
  assert.deepEqual(displayed(), ['B memory'], 'late A read cannot appear on B screen');
  assert.equal(elements['starter-question'].children.length, 23, 'PRD core questions remain optional');
  elements.content.value = '지금 쓰던 합성 초안';
  elements['starter-question'].value = '22';
  elements['starter-question'].handlers.change();
  assert.equal(elements.category.value, 'avoid_topic');
  assert.ok(elements['starter-hint'].textContent.includes('피해야'));
  assert.equal(elements.content.value, '지금 쓰던 합성 초안', 'starter choice cannot erase a draft');
  elements.category.value = 'travel';
  elements.category.handlers.change();
  assert.equal(elements['starter-question'].value, '', 'manual category choice clears the starter prompt');

  elements.patient.value = 'A';
  await elements.patient.handlers.change();
  elements.content.value = 'A save';
  const save = submit(elements['memory-form'].handlers.submit);
  await pause();
  assert.equal(posts[0].patient_id, 'A');
  elements.patient.value = 'B';
  await elements.patient.handlers.change();
  elements.content.value = 'B draft';
  firstSave.resolve(reply(201, null));
  await save;
  assert.equal(elements.content.value, 'B draft', 'late A save cannot erase B draft');
  assert.notEqual(elements['memory-status'].textContent, '확인한 기억을 저장했습니다.');

  const samePatientSave = submit(elements['memory-form'].handlers.submit);
  await pause();
  assert.equal(posts[1].patient_id, 'B');
  assert.equal(posts[1].content, 'B draft');
  elements.content.value = 'new B draft';
  elements.content.handlers.input();
  secondSave.resolve(reply(201, null));
  await samePatientSave;
  assert.equal(elements.content.value, 'new B draft', 'old B save cannot erase a newer B draft');
  assert.equal(elements['memory-status'].textContent, '이전 내용을 반영했습니다. 새 초안은 아직 저장되지 않았습니다.');
  await submit(elements['memory-form'].handlers.submit);
  assert.equal(posts[2].content, 'new B draft');
  assert.equal(elements.content.value, '', 'submitted unchanged draft is cleared after success');
  assert.equal(elements['memory-status'].textContent, '확인한 기억을 저장했습니다.');

  elements.patient.value = 'A';
  const staleRead = elements.patient.handlers.change();
  await pause();
  elements.logout.handlers.click();
  elements.email.value = 'synthetic@example.invalid';
  elements.password.value = 'synthetic';
  await submit(elements['signin-form'].handlers.submit);
  assert.deepEqual(displayed(), ['A new memory']);
  oldA.resolve(reply(403, { message: 'old session denied' }));
  await staleRead;
  assert.equal(elements['portal-card'].hidden, false, 'old session failure cannot log out the new session');
  assert.deepEqual(displayed(), ['A new memory'], 'old session failure cannot alter new memory');

  elements.patient.value = 'B';
  await elements.patient.handlers.change();
  elements.facts.children[0].children[2].handlers.click();
  assert.equal(elements.content.value, 'B memory');
  assert.equal(elements['save-memory'].textContent, '기억 수정');
  assert.equal(elements['starter-question'].disabled, true, 'editing does not override a saved fact with onboarding prompt');
  elements.category.value = 'avoid_topic';
  elements.category.handlers.change();
  elements.content.value = '가상으로 피할 주제';
  elements.content.handlers.input();
  await submit(elements['memory-form'].handlers.submit);
  assert.ok(patches[0].url.includes('fact_id=eq.B-fact'));
  assert.ok(patches[0].url.includes('patient_id=eq.B'));
  assert.equal(patches[0].headers['Content-Profile'], 'api');
  assert.equal(patches[0].headers.Prefer, 'return=representation');
  assert.deepEqual(patches[0].body, { category: 'avoid_topic', content: '가상으로 피할 주제' });
  assert.deepEqual(displayed(), [], 'avoid topic is not mixed into conversational memories');
  assert.equal(elements['avoid-facts'].children[0].children[1].textContent, '가상으로 피할 주제');
  assert.equal(elements['memory-status'].textContent, '확인한 기억을 수정했습니다.');
  assert.equal(elements['cancel-edit'].hidden, true);
  assert.equal(elements['starter-question'].disabled, false);

  elements['avoid-facts'].children[0].children[2].handlers.click();
  elements.content.value = '철회된 연결에서 저장 불가';
  elements.content.handlers.input();
  await submit(elements['memory-form'].handlers.submit);
  assert.equal(elements['memory-status'].textContent, '기억을 반영하지 못했습니다. 연결 상태를 다시 확인하세요.',
    'zero updated rows cannot be reported as a successful edit');
  assert.equal(elements.content.value, '철회된 연결에서 저장 불가');
  elements.logout.handlers.click();
  assert.equal(elements['memory-card'].hidden, true);
  assert.deepEqual(elements['avoid-facts'].children, []);
  assert.equal(elements.content.value, '');

  links.splice(0);
  elements.email.value = 'new-guardian@example.invalid';
  elements.password.value = 'synthetic-password';
  const lateSignup = elements['signup-button'].handlers.click();
  await pause();
  assert.deepEqual(signups[0].body, { email: 'new-guardian@example.invalid', password: 'synthetic-password' });
  assert.equal(signups[0].headers.Authorization, undefined, 'signup has no older session token');
  elements.logout.handlers.click();
  signupOne.resolve(reply(200, { user: { id: 'new-guardian' }, session: { access_token: 'unused' } }));
  await lateSignup;
  assert.equal(elements['portal-card'].hidden, true, 'late signup after logout cannot reopen portal');
  assert.equal(elements['signup-status'].textContent, '', 'late signup cannot restore stale confirmation text');

  elements.email.value = 'new-guardian@example.invalid';
  elements.password.value = 'synthetic-password';
  const slowLoginReply = pending();
  pausedLogin = slowLoginReply;
  const slowLogin = submit(elements['signin-form'].handlers.submit);
  await pause();
  const newerSignup = elements['signup-button'].handlers.click();
  await pause();
  slowLoginReply.resolve(reply(200, { access_token: 'old-login', user: { id: 'new-guardian' } }));
  await slowLogin;
  assert.equal(elements['portal-card'].hidden, true, 'signup supersedes a pending login');
  signupTwo.resolve(reply(200, { user: { id: 'new-guardian' }, session: { access_token: 'unused' } }));
  await newerSignup;
  assert.equal(elements['portal-card'].hidden, true, 'signup response session does not log the user in');
  assert.ok(elements['signup-status'].textContent.includes('확인 이메일'));
  assert.equal(elements.password.value, '');
  const readsBeforeLogin = aReads;
  elements.password.value = 'synthetic-password';
  await submit(elements['signin-form'].handlers.submit);
  assert.equal(elements['portal-card'].hidden, false, 'explicit login can show connection status');
  assert.equal(elements['memory-card'].hidden, true, 'account without verified links sees no memory');
  assert.equal(elements.patient.hidden, true, 'account without verified links sees no patient selector');
  assert.equal(aReads, readsBeforeLogin, 'unlinked account does not request family facts');
  elements.content.value = '연결 없는 합성 초안';
  await submit(elements['memory-form'].handlers.submit);
  assert.equal(posts.length, 3, 'unlinked account cannot save a family memory from the screen');

  elements.logout.handlers.click();
  elements.email.value = 'new-guardian@example.invalid';
  elements.password.value = 'synthetic-password';
  const staleSignup = elements['signup-button'].handlers.click();
  await pause();
  await submit(elements['signin-form'].handlers.submit);
  assert.equal(elements['portal-card'].hidden, false);
  signupThree.resolve(reply(200, { user: { id: 'new-guardian' }, session: { access_token: 'unused' } }));
  await staleSignup;
  assert.equal(elements['portal-card'].hidden, false, 'late signup cannot replace a newer login session');
  assert.equal(elements['signin-card'].hidden, true);
  console.log('Guardian portal race and draft isolation: PASS');
}

async function runSyntheticIndex() {
  const ids = [
    'signin-form', 'signin-button', 'signin-status', 'signin-card', 'email', 'password',
    'signup-button', 'signup-status', 'portal-card', 'portal-status', 'memory-card',
    'memory-form', 'memory-status', 'links', 'patient', 'facts', 'avoid-facts',
    'starter-question', 'starter-hint', 'category', 'content', 'save-memory', 'cancel-edit', 'logout',
  ];
  const elements = Object.fromEntries(ids.map(id => [id, new Element(id)]));
  const document = { body: { classList: { add() {}, remove() {} } },
    getElementById: id => elements[id], createElement: tag => new Element(tag) };
  const window = { handlers: {}, addEventListener(name, handler) { this.handlers[name] = handler; } };
  const fixture = '00000000-0000-4000-8000-000000000975';
  const other = '00000000-0000-4000-8000-000000000977';
  const guardian = '00000000-0000-4000-8000-000000000991';
  const oldFact = '00000000-0000-4000-8000-000000000901';
  const avoidFact = '00000000-0000-4000-8000-000000000911';
  const newFact = '00000000-0000-4000-8000-000000000902';
  const links = [fixture, other].map(patient_id => ({ patient_id, relationship: '가상 가족',
    access_status: 'verified', effective_at: '2020-01-01T00:00:00Z', expires_at: null }));
  const facts = [
    { fact_id: oldFact, patient_id: fixture, author_guardian_user_id: guardian,
      category: 'travel', content: '기존 가상 여행' },
    { fact_id: avoidFact, patient_id: fixture, author_guardian_user_id: guardian,
      category: 'avoid_topic', content: '가상 회피 주제' },
  ];
  let representation = true;
  const indexReplies = [];
  const indexes = [];
  const writes = [];
  async function fetch(url, options = {}) {
    if (url === '/guardian/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/token')) return reply(200, { access_token: 'guardian-synthetic-jwt', user: { id: guardian } });
    if (url.includes('/guardian_links')) return reply(200, links);
    if (url.includes('/family_context') && options.method === 'POST') {
      writes.push({ method: 'POST', body: JSON.parse(options.body), headers: options.headers });
      const row = { fact_id: representation ? newFact : '00000000-0000-4000-8000-000000000903',
        ...writes.at(-1).body };
      facts.unshift(row);
      return reply(201, representation ? [row] : null);
    }
    if (url.includes('/family_context') && options.method === 'PATCH') {
      writes.push({ method: 'PATCH', body: JSON.parse(options.body), headers: options.headers });
      const id = url.match(/fact_id=eq\.([^&]+)/)?.[1];
      const row = facts.find(item => item.fact_id === id);
      if (!row) return reply(200, []);
      Object.assign(row, writes.at(-1).body);
      return reply(200, [{ ...row }]);
    }
    if (url.includes('/family_context?patient_id=eq.')) {
      const selected = url.match(/patient_id=eq\.([^&]+)/)?.[1];
      return reply(200, selected === fixture ? facts.map(item => ({ ...item }))
        : [{ fact_id: 'B-fact', category: 'travel', content: '다른 합성 연결' }]);
    }
    if (url.startsWith(`/internal/synthetic/guardian/${fixture}/fact/`)) {
      indexes.push({ url, options });
      return indexReplies.shift()?.promise || reply(200, { status: 'ready', fact_id: url.split('/')[6] });
    }
    throw new Error(`unexpected guardian endpoint or non-fixture embedding ${url}`);
  }
  vm.runInNewContext(script, { document, window, fetch, AbortController, console });
  await pause();
  const submit = () => elements['memory-form'].handlers.submit({ preventDefault() {} });
  const login = () => elements['signin-form'].handlers.submit({ preventDefault() {} });
  const cardFor = text => elements.facts.children.find(card => card.children[1].textContent === text);
  elements.email.value = 'guardian-fixture@example.invalid';
  elements.password.value = 'synthetic';
  elements.category.value = 'travel';
  await login();
  assert.equal(elements.patient.value, fixture);
  assert.equal(cardFor('기존 가상 여행').children.length, 5, 'fixture ordinary fact has semantic status and retry');
  assert.equal(cardFor('기존 가상 여행').children[4].hidden, false,
    'previously saved but unconfirmed fact offers same-fact retry');
  assert.equal(elements['avoid-facts'].children[0].children.length, 3,
    'avoid_topic is saved-only and cannot be embedded');

  representation = false;
  elements.content.value = '응답 식별자 없는 가상 원문';
  await submit();
  assert.equal(writes[0].headers.Prefer, 'return=representation', 'fixture POST asks for actual fact_id');
  assert.equal(indexes.length, 0, '201 without returned fact_id does not claim indexing');
  assert.equal(elements.content.value, '응답 식별자 없는 가상 원문', 'uncertain save preserves typed draft');
  assert.match(elements['memory-status'].textContent, /목록 확인 전 중복 등록하거나 색인 준비를 주장하지/);
  representation = true;
  elements.content.value = '새 합성 가족 여행';
  const firstIndex = pending();
  indexReplies.push(firstIndex);
  await submit();
  assert.equal(indexes.length, 1, 'actual returned fact_id starts one semantic request');
  assert.equal(indexes[0].url, `/internal/synthetic/guardian/${fixture}/fact/${newFact}/embedding`);
  assert.equal(indexes[0].options.headers.Authorization, 'Bearer guardian-synthetic-jwt');
  assert.equal(indexes[0].options.headers['X-Synthetic-Material'], 'confirmed');
  assert.equal(indexes[0].options.body, undefined, 'embedding request has no browser-side provider key or fact body');
  assert.match(cardFor('새 합성 가족 여행').children[3].textContent, /기억 저장됨 · 의미 색인 진행 중/);
  assert.equal(cardFor('새 합성 가족 여행').children[4].hidden, true);
  firstIndex.resolve(reply(200, { status: 'ready', fact_id: newFact }));
  await pause();
  assert.match(cardFor('새 합성 가족 여행').children[3].textContent, /의미 색인 준비됨/);

  cardFor('새 합성 가족 여행').children[2].handlers.click();
  elements.content.value = '수정한 가상 여행 A';
  elements.content.handlers.input();
  const failedIndex = pending();
  indexReplies.push(failedIndex);
  await submit();
  assert.equal(writes.at(-1).method, 'PATCH');
  assert.equal(writes.at(-1).headers.Prefer, 'return=representation');
  assert.equal(indexes.at(-1).url.endsWith(`/fact/${newFact}/embedding`), true,
    'edit indexes the same returned fact_id');
  elements.content.value = '아직 저장하지 않은 새 초안 B';
  elements.content.handlers.input();
  failedIndex.resolve(reply(502, { detail: 'provider unavailable' }));
  await pause();
  assert.equal(elements['portal-card'].hidden, false, 'index provider failure keeps guardian login');
  assert.equal(elements.content.value, '아직 저장하지 않은 새 초안 B',
    'uncertain index response never clears a newer edit draft');
  assert.match(cardFor('수정한 가상 여행 A').children[3].textContent, /의미 색인 미완료/);
  assert.equal(cardFor('수정한 가상 여행 A').children[4].hidden, false);
  const retry = pending();
  indexReplies.push(retry);
  cardFor('수정한 가상 여행 A').children[4].handlers.click();
  await pause();
  assert.equal(indexes.at(-1).url.endsWith(`/fact/${newFact}/embedding`), true);
  retry.resolve(reply(200, { status: 'ready', fact_id: newFact }));
  await pause();
  assert.match(cardFor('수정한 가상 여행 A').children[3].textContent, /의미 색인 준비됨/);

  cardFor('수정한 가상 여행 A').children[2].handlers.click();
  elements.content.value = '가상 변경 버전 A';
  const oldIndex = pending();
  indexReplies.push(oldIndex);
  await submit();
  cardFor('가상 변경 버전 A').children[2].handlers.click();
  elements.content.value = '가상 변경 버전 B';
  const newerIndex = pending();
  indexReplies.push(newerIndex);
  await submit();
  oldIndex.resolve(reply(200, { status: 'ready', fact_id: newFact }));
  await pause();
  assert.match(cardFor('가상 변경 버전 B').children[3].textContent, /색인 진행 중/,
    'late A ready cannot overwrite newer B pending');
  newerIndex.resolve(reply(409, { detail: 'stale fact hash' }));
  await pause();
  assert.match(cardFor('가상 변경 버전 B').children[3].textContent, /색인 미완료/);

  const hiddenIndex = pending();
  indexReplies.push(hiddenIndex);
  cardFor('가상 변경 버전 B').children[4].handlers.click();
  await pause();
  const hiddenSignal = indexes.at(-1).options.signal;
  window.handlers.pagehide();
  assert.equal(hiddenSignal.aborted, true, 'pagehide aborts only semantic request');
  assert.equal(elements['portal-card'].hidden, false, 'pagehide does not log guardian out');
  hiddenIndex.resolve(reply(200, { status: 'ready', fact_id: newFact }));
  await pause();
  assert.match(cardFor('가상 변경 버전 B').children[3].textContent, /색인 미완료/,
    'late response after pagehide cannot claim ready');

  const switchedIndex = pending();
  indexReplies.push(switchedIndex);
  cardFor('가상 변경 버전 B').children[4].handlers.click();
  await pause();
  const switchedSignal = indexes.at(-1).options.signal;
  elements.patient.value = other;
  await elements.patient.handlers.change();
  assert.equal(switchedSignal.aborted, true, 'patient switch aborts old fixture index');
  switchedIndex.resolve(reply(200, { status: 'ready', fact_id: newFact }));
  await pause();
  assert.equal(elements.facts.children[0].children.length, 3,
    'other patient fact has no embedding/retry UI');
  assert.equal(indexes.every(call => call.url.includes(`/guardian/${fixture}/`)), true,
    'no non-fixture patient fact is transmitted for embedding');

  elements.patient.value = fixture;
  await elements.patient.handlers.change();
  const revokedIndex = pending();
  indexReplies.push(revokedIndex);
  cardFor('가상 변경 버전 B').children[4].handlers.click();
  await pause();
  revokedIndex.resolve(reply(403, { detail: 'guardian link revoked' }));
  await pause();
  assert.equal(elements['portal-card'].hidden, true, 'current index 403 hides linked family data');
  assert.equal(elements.content.value, '');
  console.log('Guardian fixed-synthetic fact save versus semantic indexing and race: PASS');
}

run().then(runSyntheticIndex).catch(error => { console.error(error); process.exitCode = 1; });
