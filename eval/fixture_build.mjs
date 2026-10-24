#!/usr/bin/env node
// Build labeled mobile fixtures for Drome's section-removal eval.
//
//   node eval/fixture_build.mjs
//
// Restores each pristine page from fixtures/mobile/.orig, injects synthetic
// unsafe units (structure-aware for the fixture kind), saves the modified
// page, and writes ground truth to fixtures/mobile/fixtures.json.
// Synthetic copy is intentionally near-real ad/comment/doom bait. Nothing
// here ships to the app.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const mobile = path.join(here, 'fixtures', 'mobile');
const orig = path.join(mobile, '.orig');

const CARD_CSS = 'padding:12px;margin:8px 0;border:1px solid #ddd;border-radius:8px;';
const COMMENT_CSS = 'padding:10px 12px;margin:10px 0;border-left:3px solid #ccc;';

const UNSAFE = {
  ad: {
    kind: 'ad-urgency-bait',
    extra: ['Open checkout now'],
    markup(head, body) {
      return (
        `<div style="${CARD_CSS}" data-fixture="synthetic-ad">` +
        `<div style="font-weight:700">${head}</div>` +
        `<p style="margin:4px 0">${body}</p>` +
        `<button style="padding:8px 12px">Open checkout now</button>` +
        `</div>`
      );
    },
  },
  doom: {
    kind: 'doom-finance',
    extra: ['Rate shock incoming — analysts:'],
    markup(head, body) {
      return (
        `<div style="${CARD_CSS}" data-fixture="synthetic-doom">` +
        `<div style="font-weight:700">${head}</div>` +
        `<p style="margin:4px 0">${body}</p>` +
        `<em>Rate shock incoming — analysts:</em>` +
        `</div>`
      );
    },
  },
  gore: {
    kind: 'gore-comment',
    extra: ['Show replies', 'hidden by moderators on desktop'],
    markup(head, body) {
      return (
        `<div style="${COMMENT_CSS}" data-fixture="synthetic-comment">` +
        `<div><strong>@gogogo27</strong> · 2 h ago</div>` +
        `<div>${head}</div>` +
        `<div style="margin-left:26px">${body} <a href="#">Show replies</a></div>` +
        `<div style="margin-left:26px;font-size:12px;color:#555">1,208 replies · hidden by moderators on desktop</div>` +
        `</div>`
      );
    },
  },
  health: {
    kind: 'panic-health',
    extra: ['Read the warning before dinner'],
    markup(head, body) {
      return (
        `<div style="${CARD_CSS}" data-fixture="synthetic-health">` +
        `<div style="font-weight:700">${head}</div>` +
        `<p style="margin:4px 0">${body}</p>` +
        `<span style="color:#b00;font-weight:600">Read the warning before dinner</span>` +
        `</div>`
      );
    },
  },
};

// Injection positions per fixture: after-content selector style anchors.
const PLAN = {
  'verge-feed': [
    { anchor: 'h2', choose: 2, kind: 'ad', place: 'after-unit' },
    { anchor: 'h2', choose: 7, kind: 'doom', place: 'after-unit' },
    { anchor: 'h2', choose: 18, kind: 'gore', place: 'after-unit' },
  ],
  'bbc-article': [
    { anchor: 'main p', choose: 4, kind: 'health', place: 'after-node' },
    { anchor: 'main p', choose: 9, kind: 'doom', place: 'after-node' },
  ],
  'aljazeera-article': [
    { anchor: 'main p', choose: 5, kind: 'gore', place: 'after-node' },
    { anchor: 'h2', choose: 3, kind: 'ad', place: 'after-unit' },
  ],
};

function argUnit(el) {
  if (!el) return el;
  const tag = el.tagName.toLowerCase();
  if (['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'span', 'a', 'em', 'strong'].includes(tag)) {
    return el.parentElement || el;
  }
  return el;
}

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const allGround = {};
const allKeep = {};

try {
  for (const [name, steps] of Object.entries(PLAN)) {
    const src = path.join(orig, `${name}.html`);
    fs.copyFileSync(src, path.join(mobile, `${name}.html`));
    const page = await browser.newPage({
      viewport: { width: 430, height: 932 },
      isMobile: true,
      hasTouch: true,
    });
    await page.goto('file://' + path.join(mobile, `${name}.html`), { waitUntil: 'domcontentloaded' });

    const hideTexts = [];
    let injectedCount = 0;
    for (const step of steps) {
      const template = UNSAFE[step.kind];
      for (const headline of [0, 1]) {
        // two synthetics per anchor: headline line 0, body line 1
      }
      const head = template.kind + ':: ' + step.anchor + ' ' + step.choose + ' — DO NOT IGNORE';
      const body = template.kind + ' body line with specifics: runs out 09:41 tonight, 500,000 deaths, blood on the windshield.';

      const param = { selector: step.anchor, choose: step.choose, place: step.place };
      const inserted = await page.evaluate(
        ({ param, html }) => {
          const inOverlay = (el) =>
            el.closest('[role="dialog"],[aria-modal="true"],[role="alertdialog"],[id*="gdpr" i],[class*="consent" i]') !== null ||
            (function fixedAncestor(node) {
              let n = node;
              while (n && n !== document.body) {
                if (getComputedStyle(n).position === 'fixed') return true;
                n = n.parentElement;
              }
              return false;
            })(el);
          const nodes = Array.from(document.querySelectorAll(param.selector))
            .filter((n) => n.isConnected && n.checkVisibility() && !inOverlay(n) && !n.closest('form, [class*="newsletter" i], [class*="opt-in" i]'));
          const node = nodes[Math.min(param.choose, nodes.length - 1)];
          if (!node) return null;
          const tpl = document.createElement('template');
          tpl.innerHTML = html;
          const synthetic = tpl.content.firstElementChild;
          let target = node;
          if (param.place === 'after-unit') {
            const unit = (function argUnitInner(el) {
              if (!el) return el;
              const tag = el.tagName.toLowerCase();
              if (['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'span', 'a', 'em', 'strong'].includes(tag)) {
                return el.parentElement || el;
              }
              return el;
            })(node);
            target = unit;
            if (target === document.body || inOverlay(target)) return null;
          }
          target.parentElement.insertBefore(synthetic, target.nextSibling);
          return synthetic ? true : false;
        },
        { param, html: template.markup(head, body) }
      );

      if (!inserted) {
        console.error(`  ! skipped ${step.kind} (${step.anchor} #${step.choose}) on ${name}`);
        continue;
      }
      hideTexts.push(head, body, ...template.extra);
      injectedCount += 1;
    }

    // Persist mutated page.
    const html = await page.evaluate(
      () => '<!doctype html>\n' + document.documentElement.outerHTML
    );
    fs.writeFileSync(path.join(mobile, `${name}.html`), html);

    // Keep-list: texts of the page's own units that must survive removal.
    await page.addScriptTag({ path: path.join(here, '..', 'Drome', 'JavaScript', 'drome-extract.js') });
    const keeps = await page.evaluate(() => {
      const synthetic = /DO NOT IGNORE|blood on the windshield|500,000 deaths|runs out 09:41|Open checkout now|Show replies|Replies hidden|Rate shock incoming|Read the warning before dinner|ad-urgency-bait|doom-finance|gore-comment|panic-health/;
      const blocks = window.__dromeExtract.collect(document.body);
      const own = blocks.filter((b) => !synthetic.test(b.text));
      const picked = [own[0], own[1], own[2], own[Math.floor(own.length / 2)], own[own.length - 2], own[own.length - 1]];
      return picked.filter(Boolean).map((b) => b.text.slice(0, 60));
    });
    allGround[name] = { hide: hideTexts.map((t) => t.replace(/\s+/g, ' ')), keep: keeps };
    console.log(`${name}: injected ${injectedCount} synthetics, ${keeps.length} keep-fragments`);

    await page.close();
  }
} finally {
  await browser.close();
}

fs.writeFileSync(
  path.join(mobile, 'fixtures.json'),
  JSON.stringify(allGround, null, 2) + '\n'
);
console.log('wrote fixtures.json');
void allKeep; void argUnit;
