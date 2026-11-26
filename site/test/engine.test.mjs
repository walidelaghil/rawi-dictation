import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const { clean } = createRequire(import.meta.url)('../engine.js');

test('English correction keeps only the corrected day', () => {
  const r = clean("so um let's meet on tuesday sorry I mean wednesday at 3 o'clock");
  assert.equal(r.text, "Let's meet on Wednesday at 3 o'clock.");
  assert.equal(r.corr, 1);
});

test('Arabic filler and spoken correction', () => {
  const r = clean('اممم يعني نخلص التقرير يوم الثلاثاء لا قصدي الأربعاء ونرسله للعميل');
  assert.equal(r.text, 'نخلص التقرير يوم الأربعاء ونرسله للعميل.');
  assert.equal(r.tag, 'AR');
});

test('English words inside an Arabic sentence stay in English', () => {
  const r = clean('اممم خلنا نأجل الـ standup لين نخلص الـ deck ونرسله للعميل');
  assert.match(r.text, /standup/);
  assert.match(r.text, /deck/);
  assert.match(r.text, /[؀-ۿ]/);
});

test('spoken ordinals become a numbered list', () => {
  const r = clean('um three things for the launch first write the release notes second record the demo third ping the beta list');
  assert.equal(r.list, true);
  assert.equal(r.text, 'Three things for the launch:\n1. Write the release notes\n2. Record the demo\n3. Ping the beta list');
});

test('a question gets a question mark', () => {
  assert.equal(clean('can we ship on friday').text, 'Can we ship on Friday?');
});

test('empty input does not throw', () => {
  assert.equal(clean('   ').text, '');
});
