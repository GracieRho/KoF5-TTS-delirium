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
    'queue-card', 'queue-refresh', 'queue-items', 'queue-status',
    'registration-card', 'registration-form', 'registration-hospital', 'registration-number',
    'registration-name', 'registration-birth', 'registration-button', 'registration-status',
    'pairing-section', 'pairing-form', 'pairing-user-id', 'pairing-button', 'pairing-status',
    'synthetic-message-section', 'synthetic-message-form', 'synthetic-message-text',
    'synthetic-message-mode', 'synthetic-message-time-wrap', 'synthetic-message-time',
    'synthetic-message-button', 'synthetic-message-review-button', 'synthetic-drafts', 'synthetic-message-status',
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
  let lateQueue = null;
  let queueReadStatus = 200;
  let queueData = [
    { patient_id: 'B', encounter_id: 'B', approved_text: '가상 B 예약 원문', due_at: '2026-09-15T04:00:00Z', delivery_status: 'pending' },
    { patient_id: 'A', encounter_id: 'A', approved_text: '가상 A 예약 원문', due_at: '2026-09-15T06:00:00Z', delivery_status: 'pending' },
    { patient_id: 'B', encounter_id: 'OLD', approved_text: '이전 입원 원문', due_at: '2026-09-15T07:00:00Z', delivery_status: 'pending' },
    { patient_id: 'A', encounter_id: 'A', approved_text: '이미 전달됨', due_at: '2026-09-15T08:00:00Z', delivery_status: 'delivered' },
  ];
  const registrationPosts = [];
  const detailReads = [];
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
    if (url.includes('/hospital_message_list?delivery_status=eq.pending')) {
      assert.equal(options.method || 'GET', 'GET', 'queue is read-only');
      return lateQueue ? lateQueue.promise : reply(queueReadStatus, queueData);
    }
    if (url.includes('hospital_context_current') || url.includes('hospital_message_list')) {
      assert.equal(options.method || 'GET', 'GET', 'hospital information remains read-only');
      detailReads.push(url);
    }
    if (url.includes('hospital_context_current?patient_id=eq.A')) {
      if (++aFacts === 1) return oldA.promise;
      return reply(200, [{ encounter_id: 'A', category: 'room', content: '새 세션 A',
        verified_at: '2026-09-15T03:00:00Z', valid_until: null }]);
    }
    if (url.includes('hospital_message_list?patient_id=eq.A')) return reply(200, [
      { encounter_id: 'A', approved_text: '가상 오후 예약', approved_by_staff_ref: 'TEST-APPROVER',
        approved_at: '2026-09-15T03:00:00Z', due_at: '2026-09-15T06:00:00Z', delivery_status: 'pending' },
    ]);
    if (url.includes('hospital_context_current?patient_id=eq.B')) {
      if (++bFacts === 2) return staleB.promise;
      return reply(200, [{ encounter_id: 'B', category: 'room', content: 'B 병실',
        verified_at: '2026-09-15T03:00:00Z', valid_until: '2026-09-16T03:00:00Z' }]);
    }
    if (url.includes('hospital_message_list?patient_id=eq.B')) return reply(200, [
      { encounter_id: 'B', approved_text: '가상 B 전달 기록', approved_by_staff_ref: 'TEST-APPROVER',
        approved_at: '2026-09-15T03:00:00Z', due_at: '2026-09-15T04:00:00Z',
        delivery_status: 'delivered', delivered_at: '2026-09-15T04:30:00Z' },
      { encounter_id: 'B', approved_text: '가상 B 예약 원문', approved_by_staff_ref: 'TEST-APPROVER',
        approved_at: '2026-09-15T03:00:00Z', due_at: '2026-09-15T06:00:00Z', delivery_status: 'pending' },
      { encounter_id: 'B', approved_text: '가상 B 취소 기록', approved_by_staff_ref: 'TEST-APPROVER',
        approved_at: '2026-09-15T03:00:00Z', due_at: '2026-09-15T07:00:00Z',
        delivery_status: 'cancelled', cancelled_at: '2026-09-15T03:30:00Z' },
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
  assert.equal(elements['queue-card'].hidden, false, 'signed-in staff can inspect the read-only pending queue');
  assert.equal(elements['queue-items'].children.length, 2, 'queue excludes old encounters and non-pending status');
  assert.equal(elements['queue-items'].children[0].children[2].textContent, '가상 B 예약 원문', 'queue preserves approved wording');
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
  assert.match(detailReads.find(url => url.includes('hospital_context_current?patient_id=eq.B')), /verified_at,valid_until/);
  assert.match(detailReads.find(url => url.includes('hospital_message_list?patient_id=eq.B')), /approved_by_staff_ref,approved_at.*delivered_at,cancelled_at/);
  assert.deepEqual(displayed(), ['B 병실']);
  assert.equal(elements.facts.children[0].children[0].textContent, '병실', 'known hospital fact category is legible in Korean');
  assert.match(elements.facts.children[0].children[2].textContent, /검증 기록.*12:00.*유효 종료.*12:00/,
    'staff can inspect the verified and expiry time of a current hospital fact');
  assert.equal(elements.messages.children[0].children[1].textContent, '가상 B 예약 원문',
    'pending approved message appears first with exact source wording');
  assert.match(elements.messages.children[1].children[2].textContent, /승인자 참조 TEST-APPROVER.*전달 기록.*13:30/,
    'delivered status includes approval attribution and timestamp');
  assert.match(elements.messages.children[2].children[2].textContent, /취소 기록.*12:30/,
    'cancelled message keeps its cancellation timestamp');
  assert.match(elements['detail-status'].textContent, /승인 사실 1건.*메시지 3건.*전달 대기 1건/);
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

  await elements['queue-items'].children[0].handlers.click();
  assert.equal(elements['detail-title'].textContent, '가상 환자 B', 'queue item opens the assigned patient detail');
  lateQueue = pending();
  const queueRefresh = elements['queue-refresh'].handlers.click();
  await pause();
  elements.logout.handlers.click();
  lateQueue.resolve(reply(200, queueData));
  await queueRefresh;
  assert.equal(elements['queue-card'].hidden, true, 'late queue refresh cannot restore messages after logout');
  assert.equal(elements['queue-items'].children.length, 0, 'logout removes pending approved text from DOM');
  lateQueue = null;
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
  assert.equal(elements['queue-items'].children.length, 0, 'patient list refresh clears potentially stale queue text');
  await elements['queue-refresh'].handlers.click();
  assert.equal(elements['queue-items'].children.length, 2, 'staff can re-read the assigned pending queue');
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
  lateReadiness = null;
  elements.email.value = 'staff@example.invalid';
  elements.password.value = 'synthetic';
  await submit();
  queueReadStatus = 403;
  await elements['queue-refresh'].handlers.click();
  assert.equal(elements['patient-card'].hidden, true, 'current queue RLS denial hides patient data');
  assert.equal(elements['queue-card'].hidden, true, 'current queue RLS denial hides approved message text');
  assert.equal(elements['queue-items'].children.length, 0);
  console.log('Hospital portal patient and session isolation: PASS');
}

async function runPairing() {
  const ids = [
    'signin-card', 'signin-form', 'signin-button', 'signin-status', 'email', 'password',
    'patient-card', 'patient-search', 'patients', 'list-status', 'logout', 'detail-card', 'detail-title',
    'detail-summary', 'facts', 'messages', 'detail-status', 'readiness-status',
    'queue-card', 'queue-refresh', 'queue-items', 'queue-status',
    'registration-card', 'registration-form', 'registration-hospital', 'registration-number',
    'registration-name', 'registration-birth', 'registration-button', 'registration-status',
    'pairing-section', 'pairing-form', 'pairing-user-id', 'pairing-button', 'pairing-status',
    'synthetic-message-section', 'synthetic-message-form', 'synthetic-message-text',
    'synthetic-message-mode', 'synthetic-message-time-wrap', 'synthetic-message-time',
    'synthetic-message-button', 'synthetic-message-review-button', 'synthetic-drafts', 'synthetic-message-status',
  ];
  const elements = Object.fromEntries(ids.map(id => [id, new Element(id)]));
  const document = { getElementById: id => elements[id], createElement: tag => new Element(tag) };
  const fixture = { patient_id: '00000000-0000-4000-8000-000000000975', encounter_id: '00000000-0000-4000-8000-000000000976',
    staff_display_name: '가상 고정 환자', ehr_patient_ref: 'TEST-975', ward_ref: '시험병동' };
  const other = { patient_id: '00000000-0000-4000-8000-000000000977', encounter_id: '00000000-0000-4000-8000-000000000978',
    staff_display_name: '가상 다른 환자', ehr_patient_ref: 'TEST-977', ward_ref: '시험병동' };
  let eligible = false;
  let readinessPending = null;
  let postPending = null;
  let postStatus = 201;
  const posts = [];
  async function fetch(url, options = {}) {
    if (url === '/portal/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/token')) return reply(200, { access_token: 'synthetic-staff-session' });
    if (url.includes('/hospital_patient_list')) return reply(200, [fixture, other]);
    if (url.includes('/hospital_registration_ready')) return reply(200, []);
    if (url.includes('/hospital_message_list?delivery_status=eq.pending')) return reply(200, []);
    if (url.includes('/hospital_context_current?patient_id=eq.') || url.includes('/hospital_message_list?patient_id=eq.')) return reply(200, []);
    if (url.includes('/synthetic_device_pairing_ready')) return readinessPending ? readinessPending.promise : reply(200,
      eligible ? [{ patient_id: fixture.patient_id, encounter_id: fixture.encounter_id }] : []);
    if (url.includes('/patient_device_pairing')) {
      posts.push({ options, payload: JSON.parse(options.body) });
      return postPending ? postPending.promise : reply(postStatus, null);
    }
    throw new Error(`unexpected pairing URL ${url}`);
  }

  vm.runInNewContext(script, { document, fetch, console });
  await pause();
  const login = () => elements['signin-form'].handlers.submit({ preventDefault() {} });
  const pair = () => elements['pairing-form'].handlers.submit({ preventDefault() {} });
  elements.email.value = 'care-staff@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  assert.equal(elements['pairing-section'].hidden, true, 'pairing form stays hidden before a fixture is selected');
  await elements.patients.children[1].handlers.click();
  assert.equal(elements['pairing-section'].hidden, true, 'other patient never opens the synthetic pairing form');
  await elements.patients.children[0].handlers.click();
  assert.equal(elements['pairing-section'].hidden, true, 'unassigned or unready staff receives no pairing form');
  eligible = true;
  await elements.patients.children[0].handlers.click();
  assert.equal(elements['pairing-section'].hidden, false, 'eligible assigned fixture opens pairing form');
  elements['pairing-user-id'].value = 'JWT-not-an-Auth-user-id';
  await pair();
  assert.equal(posts.length, 0, 'a token or malformed UUID is never posted');
  assert.match(elements['pairing-status'].textContent, /토큰은 입력하지/);

  elements['pairing-user-id'].value = '11111111-1111-4111-8111-111111111111';
  await pair();
  assert.equal(posts.length, 1);
  assert.equal(posts[0].options.headers['Content-Profile'], 'api');
  assert.equal(posts[0].options.headers.Prefer, 'return=minimal');
  assert.deepEqual(Object.keys(posts[0].payload).sort(), ['device_user_id', 'encounter_id', 'expires_at', 'patient_id']);
  assert.equal(posts[0].payload.patient_id, fixture.patient_id);
  assert.equal(posts[0].payload.encounter_id, fixture.encounter_id);
  assert.equal(posts[0].payload.device_user_id, '11111111-1111-4111-8111-111111111111');
  const hours = (Date.parse(posts[0].payload.expires_at) - Date.now()) / 3600000;
  assert.ok(hours > 6.9 && hours <= 8, 'client expiry is bounded below the DB eight-hour ceiling');
  assert.equal(elements['pairing-form'].hidden, true, 'successful request cannot be replayed without reselecting');
  assert.equal(elements['pairing-user-id'].value, '');
  assert.match(elements['pairing-status'].textContent, /합성 iPad 연결/);

  await elements.patients.children[0].handlers.click();
  postStatus = 409;
  elements['pairing-user-id'].value = '22222222-2222-4222-8222-222222222222';
  await pair();
  assert.equal(elements['pairing-form'].hidden, true, 'duplicate pairing hides the submission form');
  assert.match(elements['pairing-status'].textContent, /이미 연결/);

  await elements.patients.children[0].handlers.click();
  postStatus = 500;
  elements['pairing-user-id'].value = '33333333-3333-4333-8333-333333333333';
  await pair();
  assert.equal(elements['pairing-form'].hidden, true, 'unknown server result fails closed');
  assert.equal(elements['pairing-user-id'].value, '');

  await elements.patients.children[0].handlers.click();
  postStatus = 403;
  elements['pairing-user-id'].value = '44444444-4444-4444-8444-444444444444';
  await pair();
  assert.equal(elements['patient-card'].hidden, true, 'pairing RLS denial hides staff patient data');
  assert.equal(elements['pairing-section'].hidden, true);
  assert.equal(elements['pairing-user-id'].value, '');

  elements.email.value = 'care-staff@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  postStatus = 201;
  postPending = pending();
  await elements.patients.children[0].handlers.click();
  elements['pairing-user-id'].value = '55555555-5555-4555-8555-555555555555';
  const latePost = pair();
  await pause();
  elements.logout.handlers.click();
  postPending.resolve(reply(201, null));
  await latePost;
  assert.equal(elements['pairing-section'].hidden, true, 'late pairing POST cannot reopen after logout');
  assert.equal(elements['pairing-user-id'].value, '');

  postPending = null;
  readinessPending = pending();
  elements.email.value = 'care-staff@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  const lateReady = elements.patients.children[0].handlers.click();
  await pause();
  elements.logout.handlers.click();
  readinessPending.resolve(reply(200, [{ patient_id: fixture.patient_id, encounter_id: fixture.encounter_id }]));
  await lateReady;
  assert.equal(elements['pairing-section'].hidden, true, 'late eligibility response cannot reopen after logout');
  console.log('Hospital synthetic device pairing boundary: PASS');
}

async function runSyntheticMessage() {
  const ids = [
    'signin-card', 'signin-form', 'signin-button', 'signin-status', 'email', 'password',
    'patient-card', 'patient-search', 'patients', 'list-status', 'logout', 'detail-card', 'detail-title',
    'detail-summary', 'facts', 'messages', 'detail-status', 'readiness-status',
    'queue-card', 'queue-refresh', 'queue-items', 'queue-status',
    'registration-card', 'registration-form', 'registration-hospital', 'registration-number',
    'registration-name', 'registration-birth', 'registration-button', 'registration-status',
    'pairing-section', 'pairing-form', 'pairing-user-id', 'pairing-button', 'pairing-status',
    'synthetic-message-section', 'synthetic-message-form', 'synthetic-message-text',
    'synthetic-message-mode', 'synthetic-message-time-wrap', 'synthetic-message-time',
    'synthetic-message-button', 'synthetic-message-review-button', 'synthetic-drafts', 'synthetic-message-status',
  ];
  const elements = Object.fromEntries(ids.map(id => [id, new Element(id)]));
  const document = { getElementById: id => elements[id], createElement: tag => new Element(tag) };
  const fixture = { patient_id: '00000000-0000-4000-8000-000000000975', encounter_id: '00000000-0000-4000-8000-000000000976',
    staff_display_name: '가상 고정 환자', ehr_patient_ref: 'TEST-975', ward_ref: '시험병동' };
  const proposer = '00000000-0000-4000-8000-000000000991';
  const approver = '00000000-0000-4000-8000-000000000992';
  let activeUser = proposer;
  let postStatus = 201;
  let draftReadStatus = 200;
  let patchZero = false;
  let latePatch = null;
  let pairingReady = true;
  let pairingReadyStatus = 200;
  let latePost = null;
  const drafts = [];
  const approvedMessages = [];
  const posts = [];
  const patches = [];
  async function fetch(url, options = {}) {
    if (url === '/portal/config') return reply(200, { url: 'http://127.0.0.1:54341', publishable_key: 'sb_publishable_test' });
    if (url.includes('/auth/v1/token')) return reply(200, { access_token: `synthetic-${activeUser}`, user: { id: activeUser } });
    if (url.includes('/hospital_patient_list')) return reply(200, [fixture]);
    if (url.includes('/hospital_registration_ready')) return reply(200, []);
    if (url.includes('/hospital_message_list?delivery_status=eq.pending')) return reply(200, approvedMessages);
    if (url.includes('/hospital_context_current?patient_id=eq.')) return reply(200, []);
    if (url.includes('/hospital_message_list?patient_id=eq.')) return reply(200, approvedMessages);
    if (url.includes('/synthetic_device_pairing_ready')) return reply(pairingReadyStatus,
      pairingReadyStatus === 200 && pairingReady
        ? [{ patient_id: fixture.patient_id, encounter_id: fixture.encounter_id }] : []);
    if (url.includes('/hospital_message_list?message_id=eq.')) {
      const id = url.match(/message_id=eq\.([^&]+)/)[1];
      return reply(200, approvedMessages.filter(message => message.message_id === id));
    }
    if (url.includes('/synthetic_hospital_message_draft') && options.method === 'PATCH') {
      patches.push({ options, payload: JSON.parse(options.body) });
      const id = url.match(/draft_id=eq\.([^&]+)/)[1];
      const draft = drafts.find(item => item.draft_id === id);
      if (draft && activeUser !== draft.proposed_by_auth_user_id && !patchZero) {
        draft.status = 'approved';
        draft.approved_by_auth_user_id = activeUser;
        const approvedAt = '2026-09-16T02:00:00Z';
        approvedMessages.push({ message_id: id, patient_id: fixture.patient_id,
          encounter_id: fixture.encounter_id, approved_text: draft.proposed_text,
          approved_by_staff_ref: activeUser, approved_at: approvedAt,
          due_at: draft.schedule_mode === 'now' ? approvedAt : draft.requested_due_at,
          delivery_status: 'pending' });
      }
      return latePatch ? latePatch.promise : reply(204, null);
    }
    if (url.includes('/synthetic_hospital_message_draft') && options.method === 'POST') {
      const payload = JSON.parse(options.body);
      posts.push({ options, payload });
      const poster = activeUser;
      const record = response => {
        if (response.status === 201) drafts.push({ ...payload,
          draft_id: `00000000-0000-4000-8000-00000000090${drafts.length + 1}`,
          proposed_by_auth_user_id: poster, proposed_at: '2026-09-16T01:00:00Z', status: 'draft' });
        return response;
      };
      if (latePost) return latePost.promise.then(record);
      return record(reply(postStatus, null));
    }
    if (url.includes('/synthetic_hospital_message_draft?draft_id=eq.')) {
      const id = url.match(/draft_id=eq\.([^&]+)/)[1];
      return reply(200, drafts.filter(item => item.draft_id === id));
    }
    if (url.includes('/synthetic_hospital_message_draft?')) {
      const requestedAuthor = url.match(/proposed_by_auth_user_id=eq\.([^&]+)/)?.[1];
      return reply(draftReadStatus, draftReadStatus === 200
        ? drafts.filter(item => requestedAuthor ? item.proposed_by_auth_user_id === requestedAuthor : item.status === 'draft') : null);
    }
    throw new Error(`unexpected synthetic message URL ${url}`);
  }

  vm.runInNewContext(script, { document, fetch, console });
  await pause();
  const login = () => elements['signin-form'].handlers.submit({ preventDefault() {} });
  const compose = () => elements['synthetic-message-form'].handlers.submit({ preventDefault() {} });
  const selectFixture = () => elements.patients.children[0].handlers.click();
  elements.email.value = 'synthetic-staff@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  await selectFixture();
  assert.equal(elements['synthetic-message-section'].hidden, false, 'only ready fixture shows synthetic message forms');
  const exact = '가상 CT 촬영 예정입니다.\n원문 그대로';
  elements['synthetic-message-text'].value = exact;
  await compose();
  assert.equal(posts.length, 1);
  assert.equal(posts[0].payload.proposed_text, exact, 'draft POST preserves exact staff wording');
  assert.deepEqual(Object.keys(posts[0].payload).sort(), ['encounter_id', 'patient_id', 'proposed_text', 'schedule_mode']);
  assert.equal(posts[0].options.headers['Content-Profile'], 'api');
  assert.equal(posts[0].options.headers.Prefer, 'return=minimal');
  assert.equal(elements['synthetic-drafts'].children[0].children[1].textContent, exact);
  assert.match(elements['synthetic-drafts'].children[0].children[3].textContent, /다른 담당 직원/,
    'proposer receives no self-approval button');

  elements.logout.handlers.click();
  activeUser = approver;
  elements.email.value = 'synthetic-approver@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  await selectFixture();
  const approveButton = elements['synthetic-drafts'].children[0].children[3];
  assert.equal(typeof approveButton.handlers.click, 'function', 'distinct staff can inspect and approve exact draft');
  latePatch = pending();
  const pendingApproval = approveButton.handlers.click();
  await pause();
  elements['synthetic-message-text'].value = '승인 대기 중 작성한 새 가상 원문';
  latePatch.resolve(reply(204, null));
  await pendingApproval;
  latePatch = null;
  assert.deepEqual(patches[0].payload, { status: 'approved' }, 'PATCH contains no self-approval or rewritten text');
  assert.equal(patches[0].options.headers.Prefer, 'return=minimal');
  assert.equal(approvedMessages.length, 1);
  assert.equal(elements.messages.children[0].children[1].textContent, exact,
    'approval refreshes current patient pending message with original wording');
  assert.equal(elements['queue-items'].children[0].children[2].textContent, exact,
    'approval refreshes hospital pending queue with original wording');
  assert.match(elements['synthetic-message-status'].textContent, /실제 전달은 확인되지/);
  assert.equal(elements['synthetic-message-text'].value, '승인 대기 중 작성한 새 가상 원문',
    'approval refresh of the same fixture preserves unsent text edited during PATCH');

  elements.logout.handlers.click();
  activeUser = proposer;
  elements.email.value = 'synthetic-staff@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  await selectFixture();
  elements['synthetic-message-mode'].value = 'scheduled';
  elements['synthetic-message-mode'].handlers.change();
  assert.equal(elements['synthetic-message-time-wrap'].hidden, false);
  elements['synthetic-message-text'].value = '내일 가상 검사 예정입니다.';
  elements['synthetic-message-time'].value = '2099-01-01T12:00';
  await compose();
  assert.equal(posts[1].payload.requested_due_at, '2099-01-01T03:00:00.000Z',
    'scheduled draft converts Korean hospital time to ISO without rewriting source text');
  assert.equal(posts[1].payload.proposed_text, '내일 가상 검사 예정입니다.');

  latePost = pending();
  elements['synthetic-message-text'].value = '제출할 가상 원문 A';
  elements['synthetic-message-time'].value = '2099-03-01T12:00';
  const savingA = compose();
  await pause();
  elements['synthetic-message-text'].value = '수정 중인 가상 원문 B';
  elements['synthetic-message-time'].value = '2099-04-01T13:00';
  latePost.resolve(reply(201, null));
  await savingA;
  latePost = null;
  assert.equal(posts[2].payload.proposed_text, '제출할 가상 원문 A');
  assert.equal(elements['synthetic-message-text'].value, '수정 중인 가상 원문 B',
    'late successful POST preserves unsaved edits to the next draft');
  assert.equal(elements['synthetic-message-time'].value, '2099-04-01T13:00',
    'late successful POST preserves a changed schedule');
  assert.match(elements['synthetic-message-status'].textContent, /입력은 그대로 유지/);
  await compose();
  assert.equal(posts[3].payload.proposed_text, '수정 중인 가상 원문 B',
    'preserved edit can be submitted as a separate draft');
  assert.equal(posts[3].payload.requested_due_at, '2099-04-01T04:00:00.000Z');

  postStatus = 500;
  elements['synthetic-message-text'].value = '실패 후 보존할 가상 원문';
  elements['synthetic-message-time'].value = '2099-05-01T14:00';
  await compose();
  assert.equal(elements['synthetic-message-section'].hidden, false, 'ordinary POST failure keeps the form visible');
  assert.equal(elements['synthetic-message-text'].value, '실패 후 보존할 가상 원문');
  assert.equal(elements['synthetic-message-time'].value, '2099-05-01T14:00');
  assert.equal(elements['synthetic-message-button'].disabled, true,
    'unknown POST outcome blocks duplicate resubmission until lists are reviewed');
  assert.match(elements['synthetic-message-status'].textContent, /확인하기 전에는 재등록하지/);
  const blockedCount = posts.length;
  await compose();
  assert.equal(posts.length, blockedCount, 'disabled unknown draft outcome cannot submit again');

  elements['synthetic-message-text'].value = '실패 후 수정 중인 새 원문 B';
  elements['synthetic-message-time'].value = '2099-05-02T14:00';
  await selectFixture();
  assert.equal(elements['synthetic-message-text'].value, '실패 후 수정 중인 새 원문 B',
    'same fixture reselect does not erase unsaved text while checking uncertain POST');
  assert.equal(elements['synthetic-message-time'].value, '2099-05-02T14:00');
  assert.equal(elements['synthetic-message-button'].disabled, true,
    'no matching record keeps duplicate submission blocked after list refresh');
  assert.equal(elements['synthetic-message-review-button'].hidden, false,
    'successful list read offers explicit review before resuming');
  elements['synthetic-message-review-button'].handlers.click();
  assert.equal(elements['synthetic-message-button'].disabled, false,
    'staff review of refreshed lists resolves a no-match permanent lock');

  postStatus = 201;
  await selectFixture();
  draftReadStatus = 503;
  elements['synthetic-message-text'].value = '저장 후 조회 불명 가상 원문';
  elements['synthetic-message-time'].value = '2099-06-01T15:00';
  await compose();
  assert.equal(elements['synthetic-message-section'].hidden, false,
    'successful POST followed by failed draft GET does not hide the form');
  assert.equal(elements['synthetic-message-text'].value, '저장 후 조회 불명 가상 원문');
  assert.equal(elements['synthetic-message-time'].value, '2099-06-01T15:00');
  assert.equal(elements['synthetic-message-button'].disabled, true,
    'confirmed POST with unconfirmed list remains blocked against duplicate drafts');
  draftReadStatus = 200;
  elements['synthetic-message-text'].value = '조회 실패 뒤 수정 중인 가상 원문 B';
  elements['synthetic-message-time'].value = '2099-06-02T15:00';
  await selectFixture();
  assert.equal(elements['synthetic-message-text'].value, '조회 실패 뒤 수정 중인 가상 원문 B',
    'same fixture refresh preserves new text after POST 201 and GET 503');
  assert.equal(elements['synthetic-message-time'].value, '2099-06-02T15:00');
  assert.equal(elements['synthetic-message-button'].disabled, false,
    'finding submitted A in all-status draft list resolves uncertainty without allowing duplicate A');
  assert.equal(elements['synthetic-message-review-button'].hidden, true);

  postStatus = 500;
  elements['synthetic-message-text'].value = '자격 철회 전 미제출 가상 원문';
  elements['synthetic-message-time'].value = '2099-07-01T15:00';
  await compose();
  pairingReady = false;
  await selectFixture();
  assert.equal(elements['synthetic-message-section'].hidden, true,
    'readiness withdrawal hides synthetic composer on same fixture refresh');
  assert.equal(elements['synthetic-message-text'].value, '',
    'readiness withdrawal discards sensitive unsent text rather than preserving it');
  assert.equal(elements['synthetic-message-time'].value, '');
  pairingReady = true;
  postStatus = 201;

  await selectFixture();
  postStatus = 500;
  elements['synthetic-message-text'].value = '자격 조회 실패 전 가상 원문';
  await compose();
  pairingReadyStatus = 503;
  await selectFixture();
  assert.equal(elements['synthetic-message-section'].hidden, true);
  assert.equal(elements['synthetic-message-text'].value, '',
    'failed clinical readiness recheck discards sensitive unsent text');
  pairingReadyStatus = 200;
  postStatus = 201;

  await selectFixture();
  elements['synthetic-message-text'].value = '입원 변경 전 미제출 가상 원문';
  fixture.encounter_id = null;
  await selectFixture();
  assert.equal(elements['synthetic-message-text'].value, '',
    'same patient with changed encounter discards the previous composer');
  fixture.encounter_id = '00000000-0000-4000-8000-000000000976';

  elements.logout.handlers.click();
  activeUser = approver;
  elements.email.value = 'synthetic-approver@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  await selectFixture();
  patchZero = true;
  const zeroButton = elements['synthetic-drafts'].children[0].children[3];
  elements['synthetic-message-text'].value = '승인 실패 전 미제출 가상 원문';
  await zeroButton.handlers.click();
  assert.equal(elements['synthetic-message-section'].hidden, true,
    'zero-row PATCH return cannot be mistaken for approval');
  assert.equal(approvedMessages.length, 1);
  assert.equal(elements['synthetic-message-text'].value, '승인 실패 전 미제출 가상 원문',
    'unknown approval result does not erase unrelated unsent composer text');

  draftReadStatus = 503;
  await selectFixture();
  assert.equal(elements['synthetic-message-section'].hidden, false,
    'ready same fixture retains a visible locked composer when draft list recheck fails');
  assert.equal(elements['synthetic-message-text'].value, '승인 실패 전 미제출 가상 원문');
  assert.equal(elements['synthetic-message-button'].disabled, true);
  const beforeRetry = posts.length;
  await compose();
  assert.equal(posts.length, beforeRetry, 'failed draft list refresh cannot submit an unverified composer');
  draftReadStatus = 200;
  await selectFixture();
  assert.equal(elements['synthetic-message-text'].value, '승인 실패 전 미제출 가상 원문',
    'second same fixture reselect restores the unsent text after a failed list read');
  assert.equal(elements['synthetic-message-button'].disabled, false,
    'successful draft list refresh unlocks the preserved unsent composer');
  postStatus = 403;
  elements['synthetic-message-text'].value = '거부할 가상 원문';
  await compose();
  assert.equal(elements['patient-card'].hidden, true, 'current RLS write denial clears staff patient data');
  assert.equal(elements['synthetic-message-section'].hidden, true);

  activeUser = proposer;
  postStatus = 201;
  elements.email.value = 'synthetic-staff@example.invalid';
  elements.password.value = 'synthetic';
  await login();
  await selectFixture();
  latePost = pending();
  elements['synthetic-message-text'].value = '늦은 가상 초안';
  const pendingCompose = compose();
  await pause();
  elements.logout.handlers.click();
  latePost.resolve(reply(201, null));
  await pendingCompose;
  assert.equal(elements['synthetic-message-section'].hidden, true, 'late draft POST cannot restore form after logout');
  assert.equal(elements['synthetic-message-text'].value, '', 'logout clears pending clinical wording');
  console.log('Hospital synthetic message draft and distinct approval UI: PASS');
}

run().then(runPairing).then(runSyntheticMessage).catch(error => { console.error(error); process.exitCode = 1; });
