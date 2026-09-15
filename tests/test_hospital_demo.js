const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '../src/kof5_tts/synthetic_hospital_demo.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert.ok(script);

const elements = new Map();
for (const id of ['record', 'stop', 'withdraw', 'voice-status', 'patient-form', 'patient-case',
  'encounter-case', 'patient-summary', 'patient-id', 'patient-name', 'patient-age',
  'encounter-id', 'location', 'participation', 'voice-consent', 'assent', 'self-voice', 'dissent']) {
  elements.set(`#${id}`, { checked: false, disabled: true, hidden: true, value: '', textContent: '',
    listeners: {}, addEventListener(event, handler) { this.listeners[event] = handler; },
    fire(event, detail = {}) { this.listeners[event]?.(detail); } });
}
elements.get('#patient-case').value = 'one';
elements.get('#encounter-case').value = 'ward-a';
const pending = [];
const document = {
  hidden: false,
  querySelector: selector => elements.get(selector),
  querySelectorAll: () => ['participation', 'voice-consent', 'assent', 'self-voice', 'dissent']
    .map(id => elements.get(`#${id}`)),
  addEventListener() {},
};
class FakeRecorder {
  constructor(mediaStream) { this.mediaStream = mediaStream; this.state = 'inactive'; this.listeners = {}; }
  addEventListener(event, handler) { this.listeners[event] = handler; }
  start() { this.state = 'recording'; }
  stop() { this.state = 'inactive'; this.listeners.stop?.(); }
}
const window = { MediaRecorder: FakeRecorder, addEventListener() {} };
const navigator = { mediaDevices: { getUserMedia: () => new Promise((resolve, reject) => {
  pending.push({ resolve, reject });
}) } };
vm.runInNewContext(script, { document, window, navigator, MediaRecorder: FakeRecorder,
  performance: { now: () => 0 }, setInterval: () => 1, clearInterval() {}, Date });

const get = id => elements.get(`#${id}`);
const tick = () => new Promise(resolve => setImmediate(resolve));
const newTrack = () => ({ stopped: false, stop() { this.stopped = true; } });

async function test() {
  get('patient-form').fire('submit', { preventDefault() {} });
  for (const id of ['participation', 'voice-consent', 'assent', 'self-voice']) {
    get(id).checked = true;
    get(id).fire('change');
  }
  assert.equal(get('record').disabled, false);
  get('record').fire('click'); // Request A is still awaiting browser permission.
  get('stop').fire('click');
  get('record').fire('click'); // Request B starts after A was cancelled.
  const current = newTrack();
  pending[1].resolve({ getTracks: () => [current] });
  await tick();
  assert.equal(get('stop').disabled, false);
  pending[0].reject(new Error('late permission denial'));
  await tick();
  assert.equal(current.stopped, false, 'late denial must not stop the newer microphone');
  assert.equal(get('stop').disabled, false, 'request B remains active');
  get('stop').fire('click');
  assert.equal(current.stopped, true, 'active capture must release its own track');

  get('record').fire('click'); // Request C will be granted after it was cancelled.
  get('stop').fire('click');
  get('record').fire('click'); // Request D is active before C is granted.
  const newest = newTrack();
  pending[3].resolve({ getTracks: () => [newest] });
  await tick();
  const stale = newTrack();
  pending[2].resolve({ getTracks: () => [stale] });
  await tick();
  assert.equal(stale.stopped, true, 'late permission grant must discard its own microphone');
  assert.equal(newest.stopped, false, 'late grant must not stop the newer microphone');
  get('stop').fire('click');
  assert.equal(newest.stopped, true);
  console.log('Hospital demo mic request races passed.');
}
test().catch(error => { console.error(error); process.exitCode = 1; });
