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
    'patient-card', 'patient-search', 'patients', 'list-status', 'logout', 'detail-card', 'detail-title',
    'detail-summary', 'facts', 'messages', 'detail-status', 'readiness-status',
    'registration-card', 'registration-form', 'registration-hospital', 'registration-number',
    'registration-name', 'registration-birth', 'registration-button', 'registration-status',
  ].map(id => [id, new Element(id)]));
  const document = { getElementById: id => elements[id], createElement: tag => new Element(tag) };
  const patients = ['A', 'B'].map(patient_id => ({ patient_id, staff_display_name: `가상 환자 ${patient_id}`, ehr_patient_ref: `TEST-${patient_id}`, encounter_id: patient_id, ward_ref: '시험병동' }));
  patients.push({ patient_id: 'C', staff_display_name: '가상 환자 C', ehr_patient_ref: 'TEST-C', encounter_id: null });
  const oldA = pending();
  const staleB = pending();
  let logins = 0;
  let aFacts = 0;
  let bFacts = 0;
  let readiness = [];
  let postStatus = 201;
  let latePost = null;
  let lateReadiness = null;
  const registrationPosts = [];
  async function fetch(url, options = {}) {
    if (url === '/portal/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/token')) return reply(200, { access_token: `session-${++logins}` });
    if (url.includes('/hospital_patient_list')) return reply(200, patients);
    if (url.includes('/hospital_registration_ready')) return lateReadiness ? lateReadiness.promise : reply(200, readiness);
    if (url.includes('/hospital_patient_registration')) {
      registrationPosts.push({ options, payload: JSON.parse(options.body) });
      if (latePost) return latePost.promise;
      if (postStatus === 201) patients.push({ patient_id: 'D', ehr_patient_ref: registrationPosts.at(-1).payload.ehr_patient_ref,
        staff_display_name: registrationPosts.at(-1).payload.staff_display_name, encounter_id: null });
      return reply(postStatus, null);
    }
    if (url.includes('hospital_context_current?patient_id=eq.A')) {
      if (++aFacts === 1) return oldA.promise;
      return reply(200, [{ encounter_id: 'A', category: 'room', content: '새 세션 A' }]);
    }
    if (url.includes('hospital_message_list?patient_id=eq.A')) return reply(200, [
      { encounter_id: 'A', approved_text: '가상 오후 예약', due_at: '2026-09-15T06:00:00Z', delivery_status: 'pending' },
    ]);
    if (url.includes('hospital_context_current?patient_id=eq.B')) {
      if (++bFacts === 2) return staleB.promise;
      return reply(200, [{ encounter_id: 'B', category: 'room', content: 'B 병실' }]);
    }
    if (url.includes('hospital_message_list?patient_id=eq.B')) return reply(200, [
      { encounter_id: 'B', approved_text: '가상 B 예약', due_at: '2026-09-15T06:00:00Z', delivery_status: 'pending' },
    ]);
    throw new Error(`unexpected URL ${url}`);
  }

  vm.runInNewContext(script, { document, fetch, console });
  await pause();
  const submit = () => elements['signin-form'].handlers.submit({ preventDefault() {} });
  const displayed = () => elements.facts.children.map(card => card.children[1].textContent);
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  assert.equal(elements['registration-card'].hidden, true, 'default-deny gate keeps registration form hidden');
  assert.match(elements['list-status'].textContent, /3명의 담당 환자 중 2명이 현재 입원 중/, 'read-only list distinguishes current encounters');
  elements['patient-search'].value = 'test-b';
  elements['patient-search'].handlers.input();
  assert.deepEqual(elements.patients.children.map(button => button.hidden), [true, false, true], 'local search filters assigned patient numbers');
  assert.match(elements['list-status'].textContent, /1명의 환자/);
  elements['patient-search'].value = '';
  elements['patient-search'].handlers.input();
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
  assert.equal(elements['patient-search'].value, '', 'logout clears the patient search');
  assert.equal(elements['detail-card'].hidden, true, 'logout immediately hides hospital data');
  assert.equal(elements['detail-title'].textContent, '', 'logout removes patient name from DOM');
  assert.equal(elements['detail-summary'].textContent, '', 'logout removes patient number and location from DOM');
  assert.equal(elements['detail-status'].textContent, '', 'logout removes patient detail status from DOM');
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  await elements.patients.children[0].handlers.click();
  staleB.resolve(reply(403, { message: 'old session denied' }));
  await bRead;
  assert.equal(elements['patient-card'].hidden, false, 'old session denial cannot log out new session');
  assert.deepEqual(displayed(), ['새 세션 A'], 'old session cannot change new patient detail');
  assert.match(elements.messages.children[0].children[0].textContent, /15:00.*한국 시간/,
    'UTC device timezone still displays the 15:00 Korean hospital schedule');

  elements.logout.handlers.click();
  readiness = [{ hospital_ref: 'TEST-H1', ready: true }, { hospital_ref: 'TEST-H2', ready: true }];
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  assert.equal(elements['registration-card'].hidden, false, 'approved registrar sees the form');
  assert.equal(elements['registration-hospital'].value, 'TEST-H1');
  elements['registration-number'].value = 'TEST-WRONG-HOSPITAL';
  elements['registration-hospital'].value = 'TEST-H2';
  elements['registration-hospital'].handlers.change();
  assert.equal(elements['registration-number'].value, '', 'changing hospitals clears a previously entered patient number');
  elements['registration-hospital'].value = 'TEST-H1';
  elements['registration-hospital'].handlers.change();
  const register = () => elements['registration-form'].handlers.submit({ preventDefault() {} });
  elements['registration-number'].value = 'TEST-NEW';
  elements['registration-name'].value = '가상 신규 환자';
  elements['registration-birth'].value = '1940-01-01';
  await register();
  assert.equal(registrationPosts.length, 1);
  assert.equal(registrationPosts[0].options.headers['Content-Profile'], 'api');
  assert.deepEqual(registrationPosts[0].payload, {
    hospital_ref: 'TEST-H1', ehr_patient_ref: 'TEST-NEW', staff_display_name: '가상 신규 환자', birth_date: '1940-01-01',
  }, 'POST sends only minimum fields and never a registrar identity claim');
  assert.equal(elements.patients.children.length, 4, 'successful registration refreshes assigned patient list');
  assert.equal(elements['registration-number'].value, '', 'successful registration clears identifier input');
  postStatus = 409;
  elements['registration-number'].value = 'TEST-NEW';
  elements['registration-name'].value = '가상 신규 환자';
  await register();
  assert.match(elements['registration-status'].textContent, /이미 등록/);
  assert.equal(elements.patients.children.length, 4, 'duplicate does not add a patient');

  readiness = [{ hospital_ref: 'TEST-H1', ready: false }];
  await register();
  assert.equal(elements['registration-card'].hidden, true, 'fresh revoked gate hides the form before POST');
  assert.equal(elements['registration-number'].value, '', 'gate revocation clears hidden patient identifier');
  assert.equal(elements['registration-name'].value, '', 'gate revocation clears hidden patient name');
  assert.equal(registrationPosts.length, 2, 'revoked gate does not send another POST');
  elements.logout.handlers.click();
  readiness = [{ hospital_ref: 'TEST-H1', ready: true }];
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  postStatus = 403;
  elements['registration-number'].value = 'TEST-DENIED';
  elements['registration-name'].value = '거부 가상 환자';
  await register();
  assert.equal(elements['patient-card'].hidden, true, 'RLS denial hides patient data and registration');
  assert.equal(elements['registration-card'].hidden, true);

  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  latePost = pending();
  elements['registration-number'].value = 'TEST-LATE';
  elements['registration-name'].value = '늦은 가상 환자';
  const registration = register();
  await pause();
  elements.logout.handlers.click();
  latePost.resolve(reply(201, null));
  await registration;
  assert.equal(elements['registration-card'].hidden, true, 'late POST response cannot restore registration after logout');
  assert.equal(elements['registration-number'].value, '', 'logout clears the pending patient number');
  assert.equal(elements['registration-name'].value, '', 'logout clears the pending patient name');

  latePost = null;
  postStatus = 201;
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  lateReadiness = pending();
  elements['registration-number'].value = 'TEST-SNAPSHOT';
  elements['registration-name'].value = '가상 A 환자';
  elements['registration-birth'].value = '1940-01-01';
  const snapshot = register();
  await pause();
  for (const id of ['registration-hospital', 'registration-number', 'registration-name', 'registration-birth'])
    assert.equal(elements[id].disabled, true, `${id} is locked while approval is pending`);
  elements['registration-birth'].value = '2000-02-02'; // Simulate an out-of-band draft change despite the real UI lock.
  lateReadiness.resolve(reply(200, [{ hospital_ref: 'TEST-H1', ready: true }]));
  await snapshot;
  assert.deepEqual(registrationPosts.at(-1).payload, {
    hospital_ref: 'TEST-H1', ehr_patient_ref: 'TEST-SNAPSHOT', staff_display_name: '가상 A 환자', birth_date: '1940-01-01',
  }, 'all registration fields come from the same submit snapshot');
  assert.equal(elements['registration-birth'].disabled, false, 'completion unlocks the form');
  elements.logout.handlers.click();

  lateReadiness = pending();
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  const delayedLogin = submit();
  await pause();
  elements.logout.handlers.click();
  lateReadiness.resolve(reply(200, [{ hospital_ref: 'TEST-H1', ready: true }]));
  await delayedLogin;
  assert.equal(elements['registration-card'].hidden, true, 'late readiness cannot open registration after logout');
  assert.equal(elements['patient-card'].hidden, true, 'late login data cannot restore patients after logout');
  console.log('Hospital portal patient and session isolation: PASS');
}

run().catch(error => { console.error(error); process.exitCode = 1; });
