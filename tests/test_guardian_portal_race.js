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
  constructor(id = '') { this.id = id; this.value = ''; this.textContent = ''; this.children = []; this.handlers = {}; this.hidden = false; this.checked = false; }
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
    'voice-card', 'voice-samples', 'voice-own-confirm', 'voice-start', 'voice-stop',
    'voice-enroll', 'voice-delete', 'voice-reconcile', 'voice-refresh', 'voice-status',
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
    'voice-card', 'voice-samples', 'voice-own-confirm', 'voice-start', 'voice-stop',
    'voice-enroll', 'voice-delete', 'voice-reconcile', 'voice-refresh', 'voice-status',
  ];
  const elements = Object.fromEntries(ids.map(id => [id, new Element(id)]));
  const document = { body: { classList: { add() {}, remove() {} } },
    getElementById: id => elements[id], createElement: tag => new Element(tag),
    addEventListener() {} };
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
    if (url === `/internal/synthetic/guardian/${fixture}/voice/status`)
      return reply(200, { authorized: true, ready: false, consent_id: null,
        upload_enabled: false, clone_id: null, status: 'none' });
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

async function runSyntheticVoice() {
  const ids = [
    'signin-form', 'signin-button', 'signin-status', 'signin-card', 'email', 'password',
    'signup-button', 'signup-status', 'portal-card', 'portal-status', 'memory-card',
    'memory-form', 'memory-status', 'links', 'patient', 'facts', 'avoid-facts',
    'starter-question', 'starter-hint', 'category', 'content', 'save-memory', 'cancel-edit', 'logout',
    'voice-card', 'voice-samples', 'voice-own-confirm', 'voice-start', 'voice-stop',
    'voice-enroll', 'voice-delete', 'voice-reconcile', 'voice-refresh', 'voice-status',
  ];
  const elements = Object.fromEntries(ids.map(id => [id, new Element(id)]));
  const document = { body: { classList: { add() {}, remove() {} } },
    hidden: false, visibilityState: 'visible', handlers: {},
    getElementById: id => elements[id], createElement: tag => new Element(tag),
    addEventListener(name, handler) { this.handlers[name] = handler; } };
  const window = { handlers: {}, addEventListener(name, handler) { this.handlers[name] = handler; } };
  const fixture = '00000000-0000-4000-8000-000000000975';
  const other = '00000000-0000-4000-8000-000000000977';
  const consent = '00000000-0000-4000-8000-000000000955';
  const clone = '00000000-0000-4000-8000-000000000956';
  const links = [fixture, other].map(patient_id => ({
    patient_id, relationship: '가상 가족', access_status: 'verified',
    effective_at: '2020-01-01T00:00:00Z', expires_at: null,
  }));
  let now = Date.parse('2026-09-16T00:00:00Z');
  class ClockDate extends Date { static now() { return now; } }
  const timers = new Map();
  let nextTimer = 0;
  const tracks = [];
  const permissions = [];
  const processors = [];
  const statusReplies = [];
  const enrollReplies = [];
  const deleteReplies = [];
  const enrollCalls = [];
  const deleteCalls = [];
  let serverStatus = { authorized: true, ready: false, consent_id: null,
    upload_enabled: false, clone_id: null, status: 'none' };
  const stream = () => {
    const track = { stopped: false, stop() { this.stopped = true; } };
    tracks.push(track);
    return { getTracks: () => [track] };
  };
  const audioContexts = [];
  class AudioContext {
    constructor() {
      this.sampleRate = 16000;
      this.destination = {};
      this.closed = false;
      audioContexts.push(this);
    }
    createMediaStreamSource() { return { connect() {}, disconnect() {} }; }
    createScriptProcessor() {
      const processor = { onaudioprocess: null, connect() {}, disconnect() {} };
      processors.push(processor);
      return processor;
    }
    resume() { return Promise.resolve(); }
    close() { this.closed = true; return Promise.resolve(); }
  }
  window.AudioContext = AudioContext;
  const navigator = { mediaDevices: { getUserMedia() {
    const next = permissions.shift();
    return next ? next.promise : Promise.resolve(stream());
  } } };
  async function fetch(url, options = {}) {
    if (url === '/guardian/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/token')) return reply(200, { access_token: 'guardian-voice-jwt',
      user: { id: '00000000-0000-4000-8000-000000000991' } });
    if (url.includes('/guardian_links')) return reply(200, links);
    if (url.includes('/family_context')) return reply(200, []);
    if (url === `/internal/synthetic/guardian/${fixture}/voice/status`)
      return statusReplies.shift()?.promise || reply(200, { ...serverStatus });
    if (url === `/internal/synthetic/guardian/${fixture}/voice/enroll`) {
      enrollCalls.push({ url, options, body: JSON.parse(options.body) });
      return enrollReplies.shift()?.promise || reply(200, { status: 'verification_pending', clone_id: clone });
    }
    if (url === `/internal/synthetic/guardian/${fixture}/voice/${clone}/delete`) {
      deleteCalls.push({ url, options });
      return deleteReplies.shift()?.promise || reply(200, { status: 'deletion_pending', clone_id: clone });
    }
    if (url === `/internal/synthetic/guardian/${fixture}/voice/${clone}/reconcile`)
      return reply(200, { status: 'deletion_pending', clone_id: clone });
    throw new Error(`unexpected synthetic voice URL ${url}`);
  }
  const context = { document, window, navigator, fetch, AbortController,
    Date: ClockDate, crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000957' },
    btoa: binary => Buffer.from(binary, 'binary').toString('base64'),
    setInterval: handler => { const id = ++nextTimer; timers.set(id, handler); return id; },
    clearInterval: id => timers.delete(id), console };
  vm.runInNewContext(script, context);
  await pause();
  const login = () => elements['signin-form'].handlers.submit({ preventDefault() {} });
  elements.email.value = 'tester@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  assert.equal(elements.patient.value, fixture);
  assert.equal(elements['voice-card'].hidden, false);
  assert.equal(elements['voice-start'].disabled, true, 'no separate consent/flag keeps mic closed');
  assert.equal(tracks.length, 0);
  serverStatus = { authorized: true, ready: true, consent_id: consent,
    upload_enabled: true, clone_id: null, status: 'none' };
  await elements['voice-refresh'].handlers.click();
  assert.equal(elements['voice-start'].disabled, true, 'tester own-voice confirmation is explicit');
  elements['voice-own-confirm'].checked = true;
  elements['voice-own-confirm'].handlers.change();
  assert.equal(elements['voice-start'].disabled, false);

  const uncheckedPermission = pending();
  permissions.push(uncheckedPermission);
  const uncheckedStart = elements['voice-start'].handlers.click();
  await pause();
  elements['voice-own-confirm'].checked = false;
  elements['voice-own-confirm'].handlers.change();
  const uncheckedStream = stream();
  uncheckedPermission.resolve(uncheckedStream);
  await uncheckedStart;
  assert.equal(tracks.at(-1).stopped, true, 'unchecked own-voice confirmation closes late permission track');
  assert.equal(processors.length, 0, 'unchecked confirmation never starts PCM capture');
  assert.equal(elements['voice-card'].hidden, false, 'unchecked confirmation leaves status review visible');
  elements['voice-own-confirm'].checked = true;
  elements['voice-own-confirm'].handlers.change();
  assert.equal(elements['voice-start'].disabled, true, 'rechecking requires a fresh consent/status read');
  await elements['voice-refresh'].handlers.click();
  assert.equal(elements['voice-start'].disabled, false);

  const slowPermission = pending();
  permissions.push(slowPermission);
  const lateStart = elements['voice-start'].handlers.click();
  await pause();
  document.hidden = true;
  document.visibilityState = 'hidden';
  document.handlers.visibilitychange();
  const lateStream = stream();
  slowPermission.resolve(lateStream);
  await lateStart;
  assert.equal(tracks.at(-1).stopped, true, 'hidden pending permission closes returned track');
  assert.equal(processors.length, 0, 'hidden permission never starts PCM capture');
  assert.equal(elements['voice-enroll'].disabled, true);
  document.hidden = false;
  document.visibilityState = 'visible';
  document.handlers.visibilitychange();
  await pause();
  assert.equal(elements['voice-card'].hidden, false, 'foreground return requires fresh status to reopen panel');
  elements['voice-own-confirm'].checked = true;
  elements['voice-own-confirm'].handlers.change();

  const revokedStatus = pending();
  statusReplies.push(revokedStatus);
  const revokeStart = elements['voice-start'].handlers.click();
  await pause();
  serverStatus = { ...serverStatus, ready: false, consent_id: null };
  revokedStatus.resolve(reply(200, { ...serverStatus }));
  await revokeStart;
  assert.equal(tracks.at(-1).stopped, true, 'permission wait followed by consent withdrawal closes track');
  assert.equal(processors.length, 0);
  assert.equal(elements['voice-start'].disabled, true);
  serverStatus = { ...serverStatus, ready: true, consent_id: consent };
  await elements['voice-refresh'].handlers.click();
  elements['voice-own-confirm'].checked = true;
  elements['voice-own-confirm'].handlers.change();

  const stalePermission = pending();
  permissions.push(stalePermission);
  const startA = elements['voice-start'].handlers.click();
  await pause();
  await elements['voice-refresh'].handlers.click();
  const startB = elements['voice-start'].handlers.click();
  await startB;
  const bTrack = tracks.at(-1);
  stalePermission.resolve(Promise.reject(new Error('old permission denied')));
  await startA;
  assert.equal(bTrack.stopped, false, 'old permission failure cannot close newer capture');
  elements['voice-stop'].handlers.click();
  assert.equal(bTrack.stopped, true);
  assert.equal(elements['voice-samples'].children.length, 0, 'short discard does not create a sample');

  const staleReady = pending();
  statusReplies.push(staleReady);
  const startC = elements['voice-start'].handlers.click();
  await pause();
  const cTrack = tracks.at(-1);
  await elements['voice-refresh'].handlers.click();
  assert.equal(cTrack.stopped, true, 'refresh invalidates old pending permission stream');
  const startD = elements['voice-start'].handlers.click();
  await startD;
  const dTrack = tracks.at(-1);
  staleReady.resolve(reply(403, { detail: 'old consent denied' }));
  await startC;
  assert.equal(dTrack.stopped, false, 'stale consent 403 cannot close new capture');
  assert.equal(elements['portal-card'].hidden, false, 'stale consent 403 cannot log out newer session');
  elements['voice-stop'].handlers.click();
  assert.equal(elements['voice-samples'].children.length, 0);

  const produce = async () => {
    await elements['voice-start'].handlers.click();
    const processor = processors.at(-1);
    assert.ok(processor?.onaudioprocess, 'PCM capture starts only after fresh readiness');
    processor.onaudioprocess({ inputBuffer: { getChannelData: () => new Float32Array(16000 * 20).fill(.1) },
      outputBuffer: { getChannelData: () => new Float32Array(16000 * 20) } });
    now += 20000;
    elements['voice-stop'].handlers.click();
    assert.equal(tracks.at(-1).stopped, true);
  };
  await produce();
  assert.equal(elements['voice-samples'].children.length, 1);
  await elements['voice-start'].handlers.click();
  const uncheckedActive = tracks.at(-1);
  elements['voice-own-confirm'].checked = false;
  elements['voice-own-confirm'].handlers.change();
  assert.equal(uncheckedActive.stopped, true, 'unchecking during active capture stops mic immediately');
  assert.equal(elements['voice-samples'].children.length, 0, 'unchecking releases previously held WAV samples');
  elements['voice-own-confirm'].checked = true;
  elements['voice-own-confirm'].handlers.change();
  assert.equal(elements['voice-start'].disabled, true);
  await elements['voice-refresh'].handlers.click();
  await elements['voice-start'].handlers.click();
  const hiddenActive = tracks.at(-1);
  document.hidden = true;
  document.visibilityState = 'hidden';
  document.handlers.visibilitychange();
  assert.equal(hiddenActive.stopped, true, 'hidden active capture stops mic immediately');
  assert.equal(elements['voice-samples'].children.length, 0, 'hidden document releases prior local samples');
  document.hidden = false;
  document.visibilityState = 'visible';
  document.handlers.visibilitychange();
  await pause();
  elements['voice-own-confirm'].checked = true;
  elements['voice-own-confirm'].handlers.change();
  await produce();
  await produce();
  await produce();
  assert.equal(elements['voice-enroll'].disabled, false);
  const uncheckedPreflight = pending();
  statusReplies.push(uncheckedPreflight);
  const unconfirmedEnrollment = elements['voice-enroll'].handlers.click();
  await pause();
  elements['voice-own-confirm'].checked = false;
  elements['voice-own-confirm'].handlers.change();
  uncheckedPreflight.resolve(reply(200, { ...serverStatus }));
  await unconfirmedEnrollment;
  assert.equal(enrollCalls.length, 0, 'unchecking during fresh consent read never starts upload');
  assert.equal(elements['voice-samples'].children.length, 0, 'preflight cancellation releases all WAV samples');
  elements['voice-own-confirm'].checked = true;
  elements['voice-own-confirm'].handlers.change();
  assert.equal(elements['voice-enroll'].disabled, true);
  await elements['voice-refresh'].handlers.click();
  await produce();
  await produce();
  await produce();
  const enrollPending = pending();
  enrollReplies.push(enrollPending);
  const enrollment = elements['voice-enroll'].handlers.click();
  await pause();
  assert.equal(enrollCalls.length, 1);
  const tracksDuringUpload = tracks.length;
  assert.equal(elements['voice-refresh'].disabled, true, 'refresh cannot invalidate an in-flight upload outcome');
  await elements['voice-refresh'].handlers.click();
  await elements['voice-start'].handlers.click();
  assert.equal(tracks.length, tracksDuringUpload, 'in-flight upload cannot open a second mic capture');
  assert.equal(enrollCalls[0].body.consent_id, consent);
  assert.equal(enrollCalls[0].body.own_voice_confirmed, true);
  assert.equal(enrollCalls[0].body.samples_wav_base64.length, 3);
  assert.equal(enrollCalls[0].options.headers.Authorization, 'Bearer guardian-voice-jwt');
  assert.equal(enrollCalls[0].options.headers['X-Synthetic-Material'], 'confirmed');
  for (const encoded of enrollCalls[0].body.samples_wav_base64) {
    const wav = Buffer.from(encoded, 'base64');
    assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
    assert.equal(wav.toString('ascii', 8, 12), 'WAVE');
    assert.equal(wav.readUInt16LE(20), 1, 'PCM format');
    assert.equal(wav.readUInt16LE(22), 1, 'mono');
    assert.equal(wav.readUInt32LE(24), 16000);
    assert.equal(wav.readUInt16LE(34), 16);
    assert.equal(wav.readUInt32LE(40), 16000 * 20 * 2);
  }
  serverStatus = { authorized: true, ready: false, consent_id: null,
    upload_enabled: true, clone_id: clone, status: 'verification_pending' };
  elements['voice-own-confirm'].checked = false;
  elements['voice-own-confirm'].handlers.change();
  assert.equal(enrollCalls[0].options.signal.aborted, true, 'unchecking aborts in-flight upload request');
  enrollPending.resolve(reply(200, { status: 'verification_pending', clone_id: clone }));
  await enrollment;
  assert.match(elements['voice-status'].textContent, /결과가 아직 불명확/);
  assert.equal(elements['voice-start'].disabled, true, 'pending clone cannot reopen capture');
  assert.equal(elements['voice-samples'].children.length, 0, 'uploaded samples have no retained UI reference');
  await elements['voice-refresh'].handlers.click();
  assert.match(elements['voice-status'].textContent, /확인 대기/);
  serverStatus = { ...serverStatus, status: 'deletion_pending' };
  const deletion = elements['voice-delete'].handlers.click();
  await deletion;
  assert.equal(deleteCalls.length, 1);
  assert.ok(!/삭제가 확인됐습니다/.test(elements['voice-status'].textContent),
    'DELETE 200 with deletion_pending cannot claim remote absence');
  assert.equal(elements['voice-reconcile'].disabled, true, 'provider reconcile route is only for pending creation');
  assert.equal(elements['voice-delete'].disabled, false, 'deletion_pending can safely retry absence check');
  elements['voice-own-confirm'].checked = false;
  elements['voice-own-confirm'].handlers.change();
  assert.match(elements['voice-status'].textContent, /삭제 확인 대기/,
    'unchecking never conceals unfinished remote deletion state');
  window.handlers.pagehide();
  assert.equal(elements['voice-card'].hidden, true);
  assert.equal(elements['voice-samples'].children.length, 0);
  window.handlers.pageshow();
  await pause();
  assert.equal(elements['voice-card'].hidden, false, 'BFCache return can recheck gate without restoring audio');
  assert.equal(elements['voice-samples'].children.length, 0);
  console.log('Guardian synthetic own-voice gate, PCM16 WAV, lifecycle and uncertain remote status: PASS');
}

run().then(runSyntheticIndex).then(runSyntheticVoice)
  .catch(error => { console.error(error); process.exitCode = 1; });
