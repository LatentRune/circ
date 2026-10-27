// Screenshots each page given, cropped to what was drawn, at 2x for sharp text.
// CIRC_SHOTS_CLIP="x,y,w,h" keeps that part of the 1366x768 screen instead.
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1366, height: 768 }, deviceScaleFactor: 2 });
  for (const file of process.argv.slice(2)) {
    await page.goto('file://' + file);
    const fixed = (process.env.CIRC_SHOTS_CLIP || '').split(',').map(Number);
    const clip = fixed.length === 4 && fixed.every(n => n >= 0)
      ? { x: fixed[0], y: fixed[1], width: fixed[2], height: fixed[3] }
      : await page.evaluate(() => window.bounds());
    const out = file.replace(/\.html$/, '.png');
    await page.screenshot({ path: out, clip });
    console.log('saved ' + out);
  }
  await browser.close();
})();
