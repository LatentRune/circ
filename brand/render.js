// Renders a brand picture with headless Chromium, used by tools/brand-images.py:
//   node brand/render.js <page.html|icon.svg> <out.png> <width> <height>
const path = require('path');
const { chromium } = require('playwright');
(async () => {
  const [src, out, w, h] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: +w, height: +h } });
  const url = 'file://' + path.resolve(src);
  await page.goto(url);  // an SVG with only a viewBox fills the viewport
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  await page.screenshot({ path: out, omitBackground: true, fullPage: !src.endsWith('.svg') });
  await browser.close();
})();
