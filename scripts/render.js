// Render one draw.io file to PNG with the draw.io web app in headless Chromium.
// Usage: node render.js input.drawio output.png [scale]
// Needs the draw.io web app served on http://127.0.0.1:8765 (see render-diagrams.sh).
// Set CHROME_PATH to use an existing Chromium instead of the one Playwright installs.
const { chromium } = require('playwright');
const fs = require('fs');

(async () => {
  const [input, output, scale = '2'] = process.argv.slice(2);
  const xml = fs.readFileSync(input, 'utf8');
  const browser = await chromium.launch(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {});
  const page = await browser.newPage();
  await page.goto('http://127.0.0.1:8765/export3.html');
  await page.waitForFunction(() => typeof render === 'function');
  await page.evaluate(({ xml, scale }) =>
    render({ xml, format: 'png', scale, border: 20, bg: '#ffffff', w: 0, h: 0 }), { xml, scale });
  await page.waitForSelector('#LoadingComplete', { state: 'attached', timeout: 60000 });
  const b = JSON.parse(await page.$eval('#LoadingComplete', el => el.getAttribute('bounds')));
  const width = Math.ceil(b.x + b.width);
  const height = Math.ceil(b.y + b.height);
  await page.setViewportSize({ width, height });
  await page.screenshot({ path: output, clip: { x: 0, y: 0, width, height } });
  console.log(`${output} ${width}x${height}`);
  await browser.close();
})().catch(err => { console.error(err); process.exit(1); });
