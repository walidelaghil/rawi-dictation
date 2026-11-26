# Rawi Landing Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved Rawi landing page (artifact v24) as a plain static site in `site/`, deployable to Cloudflare Pages at `rawi.waleedelaghil.com`.

**Architecture:** No build step. `site/index.html` + `styles.css` + three scripts (`engine.js` cleanup engine, `copy.js` AR/EN strings and demo data, `app.js` UI). The engine is a UMD module so `node --test` can exercise it. `_headers` grants the microphone to the page (Salasa does the same), which the hero demo needs.

**Tech Stack:** HTML, CSS, vanilla JS, Readex Pro from Google Fonts, `node:test` for the engine, Cloudflare Pages.

## Global Constraints

- Arabic stays Arabic, English stays English; the page is a full RTL layout in Arabic (default) with a language toggle.
- No em-dashes anywhere in page copy.
- One accent (amber `#f0b04a`), dark ground `#0e1219`, Readex Pro for both scripts, pills for buttons, 16px panels, 10px inner blocks.
- The demo is labelled as an approximation of the app's cleanup.
- Vibe link opens `https://github.com/walidelaghil/rawi-dictation` in a new tab (`target="_blank" rel="noopener noreferrer"`).
- Checkout link is not decided: the buy button stays inert and is documented.
- No prices other than $29 (struck $40) for the first 10 buyers.

---

### Task 1: Cleanup engine as a tested module

**Files:**
- Create: `site/test/engine.test.mjs`
- Create: `site/engine.js`

**Interfaces:**
- Produces: `RawiEngine.clean(raw) -> {tokens:[{w,n,del}], text, tag, fills, corr, list}`, `RawiEngine.polish(s, noEnd)`, `RawiEngine.na(word)`. Global `RawiEngine` in browsers, `module.exports` in Node.

- [ ] **Step 1: Write the failing tests** (`site/test/engine.test.mjs`)

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const { clean } = createRequire(import.meta.url)('../engine.js');

test('English correction keeps only the corrected day', () => {
  const r = clean("so um let's meet on tuesday sorry I mean wednesday at 3 o'clock");
  assert.equal(r.text, "Let's meet on Wednesday at 3 o'clock.");
  assert.equal(r.corr, 1);
});
test('Arabic filler and correction', () => {
  const r = clean('اممم يعني نخلص التقرير يوم الثلاثاء لا قصدي الأربعاء ونرسله للعميل');
  assert.equal(r.text, 'نخلص التقرير يوم الأربعاء ونرسله للعميل.');
  assert.equal(r.tag, 'AR');
});
test('Arabic stays Arabic and English stays English in one sentence', () => {
  const r = clean('اممم خلنا نأجل الـ standup لين نخلص الـ deck ونرسله للعميل');
  assert.match(r.text, /standup/);
  assert.match(r.text, /deck/);
  assert.equal(r.tag, 'AR');
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
```

- [ ] **Step 2: Run, confirm failure**

Run: `node --test site/test/` — Expected: FAIL, `Cannot find module '../engine.js'`.

- [ ] **Step 3: Create `site/engine.js`** from the engine section of the approved page (the `EN_FILL` .. `polish` block), wrapped as a UMD module exporting `{clean, polish, na}`.
- [ ] **Step 4: Run, confirm pass**

Run: `node --test site/test/` — Expected: all tests pass. If an expectation is wrong about the engine's real output, fix the test only after reading the output and confirming the engine's behaviour is the intended one (it is the approved demo behaviour).
- [ ] **Step 5: Commit** `git add site/engine.js site/test && git commit -m "feat(site): cleanup engine module with tests"`

### Task 2: Assemble the static site

**Files:**
- Create: `site/index.html`, `site/styles.css`, `site/copy.js`, `site/app.js`, `site/_headers`, `site/robots.txt`, `site/assets/{insights,voice,waleed}.png`

**Interfaces:**
- Consumes: `RawiEngine` from Task 1 (`<script src="engine.js">` loaded first).
- Produces: a page that runs from any static host root.

- [ ] **Step 1:** Split the approved page: CSS to `styles.css`; strings and demo data to `copy.js` (global `RAWI_COPY`, `RAWI_DATA`); UI code to `app.js`; keep markup in `index.html` with a real `<head>` (title, description, Open Graph, favicon, preconnect, Readex Pro).
- [ ] **Step 2:** Point the Vibe button at the public repo (`target="_blank"`), keep the buy button inert.
- [ ] **Step 3:** `_headers`: `Permissions-Policy: microphone=(self)`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, long cache for `/assets/*`.
- [ ] **Step 4:** Verify with `node --check site/app.js site/copy.js site/engine.js` and `grep -c "—" site/index.html site/*.js` returns 0 for each.
- [ ] **Step 5: Commit** `git add site && git commit -m "feat(site): static landing page"`

### Task 3: Check it in a browser

- [ ] **Step 1:** `python3 -m http.server 8787 --directory site` in the background.
- [ ] **Step 2:** Open `http://localhost:8787/` in the browser pane; check Arabic and English, the demo (type, sample chips), the pre-sale pop-up, the Vibe link target, no console errors, mobile width.
- [ ] **Step 3:** Fix what shows, commit.

### Task 4: Deploy notes

**Files:**
- Create: `site/README.md`

- [ ] **Step 1:** Document Cloudflare Pages steps: new Pages project from the repo, build output directory `site`, no build command; custom domain `rawi.waleedelaghil.com` (CNAME to the `*.pages.dev` host); where to put the checkout link.
- [ ] **Step 2: Commit** `git add site/README.md && git commit -m "docs(site): deploy notes"`
