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

if (!url && !htmlPath) {
  console.error('Pass --url <url> or --html <file>');
  process.exit(2);
}

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

try {
  if (url) {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout });
    await page.waitForTimeout(500);
  } else {
    await page.goto('file://' + path.resolve(htmlPath), { waitUntil: 'domcontentloaded' });
  }

  await page.addScriptTag({ path: helper });
  const blocks = await page.evaluate(() => window.__dromeExtract.collect(document.body));
  const unique = new Set(blocks.map((block) => block.text)).size;

  console.log(`blocks=${blocks.length} unique=${unique}`);
  for (const block of blocks.slice(0, 12)) {
    console.log(`- [${block.id}] ${block.text.slice(0, 110)}`);
  }

  if (outPath) {
    fs.writeFileSync(outPath, JSON.stringify(blocks, null, 2) + '\n');
    console.log(`wrote ${outPath}`);
  }
} finally {
  await browser.close();
}
