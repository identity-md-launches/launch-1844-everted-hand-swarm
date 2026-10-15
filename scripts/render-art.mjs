// Optional asset regeneration: run python3 scripts/art.py first.
// Keep Playwright and browser downloads outside the repository.
import { pathToFileURL } from "node:url";
import { readFile } from "node:fs/promises";
const { chromium } = await import(
  process.env.IMD_PLAYWRIGHT
    ? pathToFileURL(process.env.IMD_PLAYWRIGHT).href
    : "playwright"
);
const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage({
    viewport: { width: 800, height: 620 },
    deviceScaleFactor: 1,
  });
  for (let i = 1; i <= 6; i++) {
    const svg = await readFile(
      `test/scratch/meme-render/meme-${i}.svg`,
      "utf8",
    );
    await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
    await page.screenshot({ path: `site/assets/meme-${i}.png` });
  }
  console.log(
    "Rendered six downloadable PNGs from the checked-in SVG generator.",
  );
} finally {
  await browser.close();
}
