#!/usr/bin/env node
// Extract Drome content blocks from a URL or saved HTML file using the same
// drome-extract.js helper the app injects. Requires playwright-core + Chrome.
//
//   node eval/extract_blocks.mjs --url https://example.com/article
//   node eval/extract_blocks.mjs --html /tmp/page.html --out /tmp/blocks.json

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const helper = path.join(here, '..', 'Drome', 'JavaScript', 'drome-extract.js');

function arg(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1];
}

const url = arg('--url');
const htmlPath = arg('--html');
const outPath = arg('--out');
const timeout = Number(arg('--timeout', '30000'));
const hideFile = arg('--hide');

if (!url && !htmlPath) {
  console.error('Pass --url <url> or --html <file>');
  process.exit(2);
}

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 430, height: 932 }, isMobile: true, hasTouch: true });

try {
  if (url) {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout });
    await page.waitForTimeout(500);
  } else {
    await page.goto('file://' + path.resolve(htmlPath), { waitUntil: 'domcontentloaded' });
  }

  await page.addScriptTag({ path: helper });
  const blocks = await page.evaluate(() => window.__dromeExtract.collect(document.body));

  if (hideFile) {
    const ground = JSON.parse(fs.readFileSync(path.resolve(hideFile), 'utf8'));
    const fixtureName = path.basename(htmlPath, '.html');
    // Accept both shapes: fixture-keyed (fixtures.json) and flat per-fixture labels
    let labels = ground[fixtureName];
    if (!labels && Array.isArray(ground.hide)) labels = ground;
    if (!labels) labels = { hide: [], keep: [] };
    const report = await page.evaluate((labels) => {
      // Mirror the app's hide path exactly: CSS class on the main-flagged leaf,
      // plus __drome_unsafe_hidden on the resolved section.
      const norm = (s) => s.replace(/\s+/g, ' ');
      const style = document.createElement('style');
      style.textContent = '.__drome_unsafe_hidden { display: none !important; }';
      document.head.appendChild(style);

      // Media visibility is measured through alt / aria-label / title text:
      // body.innerText does not include it, but unhidden media surface it.
      const mediaEls = [...document.querySelectorAll('img, video')];
      const mediaOf = (el) =>
        norm([el.getAttribute('alt'), el.getAttribute('aria-label'), el.getAttribute('title')]
          .map((v) => v || '').join(' '));
      const beforeMedia = mediaEls
        .map(mediaOf).filter((t) => t.length >= 25).join(' ');
      // Rendered text only: innerText still includes visually hidden
      // screen-reader labels (clipped, not display:none), which made a hidden
      // headline look "still visible".
      const visibleText = () => {
        const skipClass = /(screen-reader|sr-only|visually-hidden|a11y|offscreen)/i;
        const rendered = (el) => {
          const style = getComputedStyle(el);
          if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
          if (style.clip && style.clip !== 'auto') return false;
          if (style.clipPath && style.clipPath !== 'none') return false;
          return true;
        };
        const parts = [];
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (!node.data.trim()) continue;
          let p = node.parentElement;
          let ok = true;
          while (p && p !== document.body) {
            const cls = p.getAttribute && (p.getAttribute('class') || '');
            if ((cls && skipClass.test(cls)) || !rendered(p)) { ok = false; break; }
            p = p.parentElement;
          }
          if (ok) parts.push(node.data);
        }
        return norm(parts.join(' '));
      };
      const before = norm(visibleText() + ' ' + beforeMedia);
      const blocks = window.__dromeExtract.collect(document.body);
      const hiddenSubjects = [];
      const hiddenUnitEls = [];

      blocks.forEach((block) => {
        if (!labels.hide.some((frag) => norm(block.text).includes(norm(frag).slice(0, 40)))) return;
        try {
          const res = document.evaluate(block.xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
          const el = res.singleNodeValue;
          if (!el) return;
          const section = window.__dromeExtract.resolveSection(el);
          hiddenSubjects.push(section ? section.tagName + '.' + String(section.className).slice(0, 48) : 'LEAF ' + block.id);
          (section || el).classList.add('__drome_unsafe_hidden');
          if (section) hiddenUnitEls.push(section);
        } catch (e) {}
      });

      // Rendered text excludes display:none sections — a safe "visible" probe.
      const afterMedia = mediaEls
        .filter((m) => !m.closest('.__drome_unsafe_hidden'))
        .map(mediaOf).filter((t) => t.length >= 25).join(' ');
      const after = norm(visibleText() + ' ' + afterMedia);
      const needleOf = (frag) => norm(frag).slice(0, 40);
      const remaining = labels.hide
        .map((frag) => ({ fragment: frag.slice(0, 60), visible: after.includes(needleOf(frag)) }))
        .filter((r) => r.visible);

      // deepest element containing the fragment
      const ownerOf = (needle) => {
        for (const el of [...document.body.querySelectorAll('*')].reverse()) {
          if (!el.textContent || !norm(el.textContent).includes(needle)) continue;
          if (![...el.children].some((c) => norm(c.textContent || '').includes(needle))) return el;
        }
        // Attribute-borne text (img alt / video aria-label) is not in
        // textContent — match those against media elements directly.
        for (const m of mediaEls) {
          if (mediaOf(m).includes(needle)) return m;
        }
        return null;
      };
      // the resolved unit that envelops an element, if hidden
      const unitOf = (el) => {
        for (let n = el; n && n !== document.body; n = n.parentElement) {
          if (hiddenUnitEls.includes(n)) return n;
        }
        return null;
      };

      // keep fragments that disappeared: 'cascade' (same resolved unit as an
      // explicit flag), 'classifier-fp' (the unit is unflagged but hidden), or
      // 'outside-resolved-units' (hidden content outside any resolved unit)
      const whyHidden = labels.keep
        .map((frag) => {
          const needle = needleOf(frag);
          if (!before.includes(needle) || after.includes(needle)) return null;
          const owner = ownerOf(needle);
          const unitEl = owner ? unitOf(owner) : null;
          if (!unitEl) return { fragment: frag.slice(0, 60), kind: 'outside-resolved-units' };
          const cascade = blocks.some((b) => {
            if (!labels.hide.some((hf) => norm(b.text).includes(norm(hf).slice(0, 40)))) return false;
            try {
              const res = document.evaluate(b.xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
              return res.singleNodeValue ? unitOf(res.singleNodeValue) === unitEl : false;
            } catch (e) { return false; }
          });
          return { fragment: frag.slice(0, 60), kind: cascade ? 'cascade' : 'classifier-fp' };
        })
        .filter(Boolean);
      const collateral = whyHidden.filter((c) => c.kind !== 'cascade');
      return {
        blocks: blocks.length,
        labelsSeen: Array.isArray(labels.hide) ? labels.hide.length : -1,
        hiddenSubjects,
        remainingVisible: remaining,
        collateralHidden: collateral,
        cascadeHidden: whyHidden.length - collateral.length,
      };
    }, labels);

    const removedAll = report.remainingVisible.length === 0;
    const noCollateral = report.collateralHidden.length === 0;
    console.log(
      `${fixtureName}: blocks=${report.blocks} resolvedUnits=${report.hiddenSubjects.length} removedAll=${removedAll} noCollateral=${noCollateral}`
    );
    for (const r of report.remainingVisible) console.log(`  ✗ STILL VISIBLE: ${r.fragment}…`);
    for (const c of report.collateralHidden) console.log(`  ✗ WRONGLY HIDDEN: ${c.fragment}…`);
    if (!removedAll || !noCollateral) console.log(`  resolved to: ${report.hiddenSubjects.join(' | ')}`);
    if (outPath) fs.writeFileSync(outPath, JSON.stringify(report, null, 2) + '\n');
  } else {
    const unique = new Set(blocks.map((block) => block.text)).size;

    console.log(`blocks=${blocks.length} unique=${unique}`);
    for (const block of blocks.slice(0, 12)) {
      console.log(`- [${block.id}] ${block.text.slice(0, 110)}`);
    }

    if (outPath) {
      fs.writeFileSync(outPath, JSON.stringify(blocks, null, 2) + '\n');
      console.log(`wrote ${outPath}`);
    }
  }
} finally {
  await browser.close();
}
