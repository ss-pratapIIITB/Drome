#!/usr/bin/env node
// Save a real page as a self-contained fixture for offline extraction evals.
//
//   node eval/save_fixture.mjs --url https://… --out fixtures/mobile/name.html
//
// Opens the page with an iPhone user agent (mobile-first layout), waits for
// the DOM to settle, scrolls to trigger lazy loads, strips obvious consent
// banners, then writes the outerHTML of the document to --out.

import fs from 'node:fs';
import { chromium } from 'playwright-core';

function arg(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? null : process.argv[index + 1];
}

const url = arg('--url');
const out = arg('--out');

if (!url || !out) {
  console.error('Usage: save_fixture.mjs --url <url> --out <fixtures/mobile/name.html>');
  process.exit(2);
}

const iPhoneUa =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const context = await browser.newContext({
  userAgent: iPhoneUa,
  viewport: { width: 430, height: 932 },
  deviceScaleFactor: 3,
  isMobile: true,
  hasTouch: true
});
const page = await context.newPage();

try {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
  await page.evaluate(async () => {
    const pause = (ms) => new Promise((r) => setTimeout(r, ms));
    for (let y = 0; y < 6000; y += 900) {
      window.scrollTo(0, y);
      await pause(220);
    }
    window.scrollTo(0, 0);
    await pause(300);
  });
  await page.waitForTimeout(900);

  const html = await page.evaluate(() => {
    const drop = (sel) => document.querySelectorAll(sel).forEach((n) => n.remove());
    drop('[id*="gdpr" i]'); drop('[class*="consent" i]');
    drop('[class*="cookie" i]'); drop('[id*="cookie" i]');
    // Freeze the page: scripts re-run on fixture load and their failed network
    // calls wipe server-rendered content (hydration). A static copy keeps the
    // DOM that users actually see.
    drop('script'); drop('noscript'); drop('iframe');
    return '<!doctype html>\n' + document.documentElement.outerHTML;
  });

  fs.writeFileSync(out, html);
  console.log(`saved ${out} (${(html.length / 1024).toFixed(0)} KiB)`);
} finally {
  await browser.close();
}
