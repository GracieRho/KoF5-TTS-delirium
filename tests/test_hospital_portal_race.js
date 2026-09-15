const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('src/kof5_tts/hospital_portal.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const pause = () => new Promise(resolve => setImmediate(resolve));
const pending = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};
const reply = (status, data) => ({ ok: status >= 200 && status < 300, status, json: async () => data });

class Element {
  constructor(id = '') { this.id = id; this.value = ''; this.textContent = ''; this.children = []; this.handlers = {}; this.hidden = false; this.dataset = {}; }
  addEventListener(name, handler) { this.handlers[name] = handler; }
  replaceChildren() { this.children = []; this.textContent = ''; }
  append(...items) { this.children.push(...items); }
  setAttribute(name, value) { this[name] = value; }
  querySelectorAll() { return this.children; }
}

async function run() {
  const elements = Object.fromEntries([
    'signin-card', 'signin-form', 'signin-button', 'signin-status', 'email', 'password',
    'patient-card', 'patients', 'list-status', 'logout', 'detail-card', 'detail-title',
    'detail-summary', 'facts', 'messages', 'detail-status',
  ].map(id => [id, new Element(id)]));
  const document = { getElementById: id => elements[id], createElement: tag => new Element(tag) };
  const patients = ['A', 'B'].map(patient_id => ({ patient_id, staff_display_name: `가상 환자 ${patient_id}`, ehr_patient_ref: `TEST-${patient_id}`, encounter_id: patient_id, ward_ref: '시험병동' }));
  patients.push({ patient_id: 'C', staff_display_name: '가상 환자 C', ehr_patient_ref: 'TEST-C', encounter_id: null });
  const oldA = pending();
  const staleB = pending();
  let logins = 0;
  let aFacts = 0;
  let bFacts = 0;
  async function fetch(url) {
    if (url === '/portal/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/token')) return reply(200, { access_token: `session-${++logins}` });
    if (url.includes('/hospital_patient_list')) return reply(200, patients);
    if (url.includes('hospital_context_current?patient_id=eq.A')) {
      if (++aFacts === 1) return oldA.promise;
      return reply(200, [{ encounter_id: 'A', category: 'room', content: '새 세션 A' }]);
    }
    if (url.includes('hospital_message_list?patient_id=eq.A')) return reply(200, []);
    if (url.includes('hospital_context_current?patient_id=eq.B')) {
      if (++bFacts === 2) return staleB.promise;
      return reply(200, [{ encounter_id: 'B', category: 'room', content: 'B 병실' }]);
    }
    if (url.includes('hospital_message_list?patient_id=eq.B')) return reply(200, []);
    throw new Error(`unexpected URL ${url}`);
  }

  vm.runInNewContext(script, { document, fetch, console });
  await pause();
  const submit = () => elements['signin-form'].handlers.submit({ preventDefault() {} });
  const displayed = () => elements.facts.children.map(card => card.children[1].textContent);
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  const aRead = elements.patients.children[0].handlers.click();
  await pause();
  await elements.patients.children[1].handlers.click();
  assert.deepEqual(displayed(), ['B 병실']);
  oldA.resolve(reply(200, [{ encounter_id: 'A', category: 'room', content: '오래된 A 병실' }]));
  await aRead;
  assert.deepEqual(displayed(), ['B 병실'], 'late A fact cannot appear for B');

  await elements.patients.children[2].handlers.click();
  assert.equal(elements['detail-card'].hidden, false);
  assert.match(elements.facts.textContent, /현재 입원이 없어/, 'no encounter shows no hospital facts');

  const bRead = elements.patients.children[1].handlers.click();
  await pause();
  elements.logout.handlers.click();
  assert.equal(elements['detail-card'].hidden, true, 'logout immediately hides hospital data');
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  await elements.patients.children[0].handlers.click();
  staleB.resolve(reply(403, { message: 'old session denied' }));
  await bRead;
  assert.equal(elements['patient-card'].hidden, false, 'old session denial cannot log out new session');
  assert.deepEqual(displayed(), ['새 세션 A'], 'old session cannot change new patient detail');
  console.log('Hospital portal patient and session isolation: PASS');
}

run().catch(error => { console.error(error); process.exitCode = 1; });
