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
  replaceChildren() { this.children = []; this.textContent = ''; if (this.id === 'patient') this.value = ''; }
  append(...children) { this.children.push(...children); if (this.id === 'patient' && !this.value) this.value = children[0].value; }
}

async function run() {
  const elements = Object.fromEntries([
    'signin-form', 'signin-button', 'signin-status', 'signin-card', 'email', 'password',
    'portal-card', 'portal-status', 'memory-card', 'memory-form', 'memory-status',
    'links', 'patient', 'facts', 'category', 'content', 'logout',
  ].map(id => [id, new Element(id)]));
  const body = { classList: { add() {}, remove() {} } };
  const document = { body, getElementById: id => elements[id], createElement: tag => new Element(tag) };
  const firstA = pending();
  const oldA = pending();
  const firstSave = pending();
  const secondSave = pending();
  const posts = [];
  let aReads = 0;
  let logins = 0;
  const links = ['A', 'B'].map(patient_id => ({ patient_id, relationship: '가상 가족', access_status: 'verified', effective_at: '2020-01-01T00:00:00Z', expires_at: null }));

  async function fetch(url, options = {}) {
    if (url === '/guardian/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/token')) return reply(200, { access_token: `session-${++logins}`, user: { id: 'guardian' } });
    if (url.includes('/guardian_links')) return reply(200, links);
    if (url.includes('/family_context') && options.method === 'POST') {
      posts.push(JSON.parse(options.body));
      if (posts.length === 1) return firstSave.promise;
      if (posts.length === 2) return secondSave.promise;
      return reply(201, null);
    }
    if (url.includes('patient_id=eq.A')) {
      aReads += 1;
      if (aReads === 1) return firstA.promise;
      if (aReads === 3) return oldA.promise;
      return reply(200, [{ category: 'travel', content: 'A new memory' }]);
    }
    if (url.includes('patient_id=eq.B')) return reply(200, [{ category: 'travel', content: 'B memory' }]);
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
  firstA.resolve(reply(200, [{ category: 'travel', content: 'A memory' }]));
  await login;
  assert.deepEqual(displayed(), ['B memory'], 'late A read cannot appear on B screen');

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
  assert.equal(elements['memory-status'].textContent, '이전 내용을 저장했습니다. 새 초안은 아직 저장되지 않았습니다.');
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
  console.log('Guardian portal race and draft isolation: PASS');
}

run().catch(error => { console.error(error); process.exitCode = 1; });
