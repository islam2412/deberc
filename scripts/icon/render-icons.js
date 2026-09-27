// Рисует три варианта иконки из icon.html и кладёт их в Assets.xcassets/AppIcon.appiconset.
// Запуск: node scripts/icon/render-icons.js
// Playwright берётся из NODE_PATH или из PLAYWRIGHT_MODULE (путь к модулю playwright).
// Проверка результата: основная иконка — RGB без альфа-канала (иначе App Store отклонит сборку),
// тёмная — с прозрачным фоном, тонированная — непрозрачные оттенки серого.
const path = require('path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const root = path.resolve(__dirname, '..', '..');
const out = path.join(root, 'Deberc', 'Assets.xcassets', 'AppIcon.appiconset');
const variants = [
  { cls: 'any', file: 'AppIcon.png', transparent: false },
  { cls: 'dark', file: 'AppIcon-Dark.png', transparent: true },
  { cls: 'tinted', file: 'AppIcon-Tinted.png', transparent: false },
];

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(__dirname, 'icon.html'));
  for (const v of variants) {
    await page.evaluate((cls) => { document.body.className = cls; }, v.cls);
    await page.waitForTimeout(250);
    await page.screenshot({ path: path.join(out, v.file), omitBackground: v.transparent });
    console.log('Готово:', path.join(out, v.file));
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
