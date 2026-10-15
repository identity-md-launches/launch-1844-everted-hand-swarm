import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { extname, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import assert from "node:assert/strict";
const { chromium, webkit } = await import(
  process.env.IMD_PLAYWRIGHT
    ? pathToFileURL(process.env.IMD_PLAYWRIGHT).href
    : "playwright"
);
const AxeModule = process.argv.includes("--a11y")
  ? await import(
      process.env.IMD_AXE_PLAYWRIGHT
        ? pathToFileURL(process.env.IMD_AXE_PLAYWRIGHT).href
        : "@axe-core/playwright"
    )
  : null;
const AxeBuilder =
  AxeModule &&
  (typeof AxeModule.default === "function"
    ? AxeModule.default
    : AxeModule.default.default);
const root = resolve("dist"),
  out = resolve("test/scratch/browser");
await mkdir(out, { recursive: true });
if (process.argv.includes('--evidence')) await mkdir('artifacts/screenshots', { recursive: true });
const mime = {
  ".html": "text/html",
  ".css": "text/css",
  ".js": "text/javascript",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".woff2": "font/woff2",
  ".json": "application/json",
};
const server = createServer(async (req, res) => {
  const pathname = new URL(req.url, "http://local").pathname;
  if (pathname === "/simd-coin.json") {
    res.writeHead(200, { "Content-Type": "application/json" }).end("{}");
    return;
  }
  let relative = pathname.replace(/^\/preview\//, "/");
  if (relative.endsWith("/")) relative += "index.html";
  const file = resolve(root, "." + relative);
  if (!file.startsWith(root + "/")) {
    res.writeHead(403).end();
    return;
  }
  try {
    const body = await readFile(file);
    res
      .writeHead(200, {
        "Content-Type": mime[extname(file)] || "application/octet-stream",
      })
      .end(body);
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const url = `http://127.0.0.1:${server.address().port}/preview/`;
const results = [];
const check = (name, detail = "passed") => {
  results.push({ name, result: detail });
  console.log(`${name}: ${detail}`);
};
const engines = process.argv.includes("--webkit")
  ? [["webkit", webkit]]
  : [["chromium", chromium]];
try {
  for (const [name, engine] of engines) {
    const browser = await engine.launch({ headless: true });
    try {
      const context = await browser.newContext({
        viewport: { width: 390, height: 844 },
        reducedMotion: "reduce",
      });
      const page = await context.newPage();
      const errors = [],
        badResources = [],
        consoleErrors = [];
      page.on('console', message => { if(message.type()==='error') consoleErrors.push({text:message.text(),url:message.location().url}); });
      page.on("pageerror", (error) => errors.push(error.message));
      page.on("response", (response) => {
        if (response.status() >= 400) badResources.push(response.url());
      });
      await page.goto(url);
      await page.evaluate(() => document.fonts.ready);
      assert.equal(await page.locator("#hero-title").isVisible(), true);
      const buyBox = await page.locator(".hero .buy-link").boundingBox();
      assert.ok(buyBox.y + buyBox.height < 844);
      check(`${name}: product and main action on the 390px first screen`);
      await page.screenshot({ path: `${out}/${name}-390-light.png` });
      assert.equal(
        await page.locator("#contract-address").innerText(),
        "launching…",
      );
      assert.equal(await page.locator("#copy-contract").isDisabled(), true);
      assert.equal(await page.locator("#stats").isVisible(), false);
      assert.equal(
        await page.locator(".hero .buy-link").getAttribute("href"),
        "#buy",
      );
      check(`${name}: truthful prelaunch state, no fabricated values`);
      await page.locator("#menu-toggle").click();
      assert.equal(
        await page.locator("#menu-toggle").getAttribute("aria-expanded"),
        "true",
      );
      await page.keyboard.press("Escape");
      assert.equal(
        await page.locator("#menu-toggle").getAttribute("aria-expanded"),
        "false",
      );
      assert.equal(
        await page
          .locator("#menu-toggle")
          .evaluate((el) => el === document.activeElement),
        true,
      );
      check(`${name}: mobile menu opens, closes, and returns focus`);
      await page.locator("#sprout").click();
      assert.match(await page.locator("#sprout-count").innerText(), /^1 hand/);
      await page.locator("#sprout").focus();
      await page.keyboard.press("Enter");
      assert.match(await page.locator("#sprout-count").innerText(), /^2 hands/);
      await page.locator("#logo-sticker").focus();
      await page.keyboard.press("ArrowRight");
      assert.equal(
        await page
          .locator("#logo-sticker")
          .evaluate((el) => el.style.getPropertyValue("--dx")),
        "12px",
      );
      await page.locator("#reset-swarm").click();
      assert.match(await page.locator("#sprout-count").innerText(), /^0 hands/);
      assert.equal(
        await page.evaluate(
          () =>
            document
              .getAnimations()
              .filter(
                (a) =>
                  a.playState === "running" &&
                  a.effect.getTiming().iterations === Infinity,
              ).length,
        ),
        0,
      );
      check(
        `${name}: swarm count, keyboard sprouting, drag alternative, reset and reduced motion`,
      );
      const sealBox = await page.locator("#logo-sticker").boundingBox();
      await page.mouse.move(
        sealBox.x + sealBox.width / 2,
        sealBox.y + sealBox.height / 2,
      );
      await page.mouse.down();
      await page.mouse.move(
        sealBox.x + sealBox.width / 2 + 30,
        sealBox.y + sealBox.height / 2 + 20,
        { steps: 4 },
      );
      await page.mouse.up();
      assert.notEqual(
        await page
          .locator("#logo-sticker")
          .evaluate((el) => el.style.getPropertyValue("--dx")),
        "0px",
      );
      assert.match(await page.locator("#sprout-count").innerText(), /^0 hands/);
      check(`${name}: pointer dragging moves the seal without a false click`);
      await page.locator("#step-tab-1").click();
      await page.keyboard.press("ArrowRight");
      assert.equal(
        await page.locator("#step-tab-2").getAttribute("aria-selected"),
        "true",
      );
      assert.equal(await page.locator("#step-2").isVisible(), true);
      await page.keyboard.press("End");
      assert.equal(await page.locator("#step-3").isVisible(), true);
      await page.locator("#next-step").click();
      assert.equal(await page.locator("#step-1").isVisible(), true);
      check(`${name}: how-to-buy tabs, arrow keys, End and next-step cycle`);
      // The live endpoint fixture uses the known IMD address to exercise formatting only.
      // It is never written into the site or represented as a deployed EHS address.
      const fixture = {
        token: "0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7",
        coinUrl: "https://www.si-md.xyz/launchpad",
        chartUrl:
          "https://dexscreener.com/ethereum/0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7",
        market: { priceUsd: 0.000025, marketCap: 25000, volume24h: 0 },
        logo: `https://evertedhandswarm.si-md.xyz/assets/logo.jpg`,
      };
      await page.route(
        "https://evertedhandswarm.si-md.xyz/assets/logo.jpg",
        (route) =>
          route.fulfill({
            status: 200,
            contentType: "image/jpeg",
            path: resolve("dist/assets/logo.jpg"),
          }),
      );
      await page.route("**/simd-coin.json", (route) =>
        route.fulfill({ json: fixture }),
      );
      await page.locator("#refresh-stats").click();
      await page.waitForFunction(
        () => !document.querySelector("#stats").hidden,
      );
      assert.equal(
        await page.locator(".hero .buy-link").getAttribute("href"),
        fixture.coinUrl,
      );
      assert.equal(
        await page.locator(".hero .chart-link").getAttribute("href"),
        fixture.chartUrl,
      );
      assert.equal(
        await page.locator("#contract-address").innerText(),
        fixture.token,
      );
      assert.equal(await page.locator("#volume-value").innerText(), "$0");
      assert.equal(
        await page.locator("#hero-logo").getAttribute("src"),
        fixture.logo,
      );
      await page.evaluate(() => {
        window.__copied = "";
        Object.defineProperty(navigator, "clipboard", {
          configurable: true,
          value: {
            writeText: async (text) => {
              window.__copied = text;
            },
          },
        });
      });
      await page.locator("#copy-contract").click();
      assert.equal(await page.evaluate(() => window.__copied), fixture.token);
      await page.locator("#copy-link").click();
      assert.equal(
        await page.evaluate(() => window.__copied),
        "https://evertedhandswarm.si-md.xyz/",
      );
      for (let i = 1; i <= 3; i++) {
        const href = await page.locator(`#share-${i}`).getAttribute("href");
        assert.equal(new URL(href).hostname, "x.com");
        assert.ok(new URL(href).searchParams.get("text"));
      }
      check(
        `${name}: live values, zero volume, supplied logo, Buy/Chart URLs, copy controls and three share intents`,
      );
      assert.equal(await page.locator("iframe").count(), 0);
      await page.route("https://dexscreener.com/**", (route) =>
        route.fulfill({
          contentType: "text/html",
          body: "<!doctype html><title>Test chart frame</title><p>Isolated test frame</p>",
        }),
      );
      await page.locator("#load-chart").click();
      assert.equal(await page.locator("iframe").count(), 1);
      assert.equal(
        new URL(
          await page.locator("iframe").getAttribute("src"),
        ).searchParams.get("embed"),
        "1",
      );
      check(
        `${name}: DexScreener embed is opt-in and has the required parameters`,
      );
      await page.unroute("**/simd-coin.json");
      await page.route("**/simd-coin.json", (route) => route.abort("failed"));
      await page.locator("#refresh-stats").click();
      await page.waitForFunction(() =>
        document
          .querySelector("#data-status")
          .textContent.includes("Last known"),
      );
      assert.equal(await page.locator("#stats").isVisible(), true);
      check(`${name}: failed refresh retains and labels last known data`);
      await page.unroute("**/simd-coin.json");
      await page.route("**/simd-coin.json", (route) =>
        route.fulfill({ json: {} }),
      );
      await page.locator("#refresh-stats").click();
      await page.waitForFunction(() => document.querySelector("#stats").hidden);
      for (const lang of ["en", "es", "zh"]) {
        await page.locator("#language").selectOption(lang);
        assert.equal(
          await page.locator("html").getAttribute("lang"),
          lang === "zh" ? "zh-CN" : lang,
        );
        for (const width of [320, 375, 390, 768, 1440, 1920]) {
          await page.setViewportSize({ width, height: 900 });
          assert.ok(
            await page.evaluate(
              () => document.documentElement.scrollWidth <= innerWidth + 1,
            ),
            `${name} ${lang} overflow at ${width}`,
          );
        }
      }
      await page.locator("#language").selectOption("es");
      await page.reload();
      assert.equal(await page.locator("html").getAttribute("lang"), "es");
      await page.locator("#language").selectOption("en");
      check(
        `${name}: EN / ES / 中文 reflow at 320, 375, 390, 768, 1440 and 1920px; language persists`,
      );
      if (AxeBuilder) {
        for (const theme of ["light", "dark"]) {
          if ((await page.locator("html").getAttribute("data-theme")) !== theme)
            await page.locator("#theme-toggle").click();
          for (const width of [375, 1440]) {
            await page.setViewportSize({ width, height: 900 });
            const audit = await new AxeBuilder({ page })
              .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
              .analyze();
            await writeFile(
              `${out}/${name}-axe-${theme}-${width}.json`,
              JSON.stringify(
                {
                  violations: audit.violations,
                  incomplete: audit.incomplete.map((x) => ({
                    id: x.id,
                    impact: x.impact,
                    nodes: x.nodes.map((n) => ({
                      target: n.target,
                      summary: n.failureSummary,
                    })),
                  })),
                  passes: audit.passes.length,
                },
                null,
                2,
              ),
            );
            assert.deepEqual(
              audit.violations.map((v) => ({
                id: v.id,
                nodes: v.nodes.map((n) => n.target),
              })),
              [],
            );
          }
        }
        if ((await page.locator("html").getAttribute("data-theme")) !== "light")
          await page.locator("#theme-toggle").click();
        check(
          `${name}: axe WCAG A/AA scan, light/dark at 375/1440: zero violations`,
        );
      }
      // Restore real empty state for visual evidence; screenshots never show fixture market data.
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.evaluate(async () => {
        for (const img of document.images) img.loading = "eager";
        await Promise.all(
          [...document.images].map((img) => img.decode().catch(() => {})),
        );
        window.scrollTo(0, 0);
      });
      assert.equal(
        await page.evaluate(
          () =>
            [...document.images].filter(
              (img) => !img.complete || img.naturalWidth === 0,
            ).length,
        ),
        0,
      );
      await page.screenshot({
        path: `${out}/${name}-1440-light-full.png`,
        fullPage: true,
      });
      await page.locator("#theme-toggle").click();
      await page.reload();
      assert.equal(
        await page.locator("html").getAttribute("data-theme"),
        "dark",
      );
      await page.evaluate(async () => {
        for (const img of document.images) img.loading = "eager";
        await Promise.all(
          [...document.images].map((img) => img.decode().catch(() => {})),
        );
        window.scrollTo(0, 0);
      });
      await page.screenshot({ path: `${out}/${name}-1440-dark.png` });
      if (process.argv.includes('--evidence')) await page.screenshot({path:'artifacts/screenshots/desktop-dark.jpg',type:'jpeg',quality:82});
      await page.screenshot({
        path: `${out}/${name}-1440-dark-full.png`,
        fullPage: true,
      });
      await page.setViewportSize({ width: 390, height: 844 });
      await page.screenshot({ path: `${out}/${name}-390-dark.png` });
      if (process.argv.includes('--evidence')) await page.screenshot({path:'artifacts/screenshots/mobile-dark.jpg',type:'jpeg',quality:85});
      check(`${name}: theme persists; all media decode; both themes captured`);
      const download = page.waitForEvent("download");
      await page.locator(".meme a[download]").first().click();
      assert.equal(
        (await download).suggestedFilename(),
        "EHS-multiplying-hands.png",
      );
      for (let i = 1; i <= 6; i++) {
        const response = await context.request.get(
          url + `assets/meme-${i}.png`,
        );
        assert.equal(response.status(), 200);
        assert.ok((await response.body()).length > 10000);
      }
      check(`${name}: meme download interaction and all six PNGs`);
      await page.evaluate(
        () => (document.documentElement.style.fontSize = "200%"),
      );
      await page.screenshot({ path: `${out}/${name}-200-text.png` });
      if (
        !(await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ))
      )
        console.log(
          await page.evaluate(() =>
            [...document.querySelectorAll("body *")]
              .filter((el) => el.getBoundingClientRect().right > innerWidth + 1)
              .map((el) => ({
                tag: el.tagName,
                id: el.id,
                cls: el.className,
                width: el.getBoundingClientRect().width,
                right: el.getBoundingClientRect().right,
              }))
              .slice(0, 30),
          ),
        );
      assert.ok(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      );
      await page.evaluate(() => (document.documentElement.style.fontSize = ""));
      check(
        `${name}: 200% text enlargement reflows without horizontal overflow`,
      );
      for (const width of [375, 1440]) {
        await page.setViewportSize({ width, height: 900 });
        await page.goto(url + "404.html");
        assert.equal(
          await page.locator("#error-back").getAttribute("href"),
          "./",
        );
        assert.ok(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth + 1,
          ),
        );
        await page.screenshot({ path: `${out}/${name}-404-${width}.png` });
      }
      check(`${name}: 404 page renders at 375 / 1440, return link resolves`);
      assert.deepEqual(errors, []);
      assert.deepEqual(badResources, []);
      assert.deepEqual(consoleErrors.filter(error=>!error.url?.endsWith('/simd-coin.json')), []);
      check(
        `${name}: zero uncaught script errors and zero failed HTTP resources`,
      );
      check(`${name}: zero unexpected console errors (the simulated API outage is expected)`);
      await context.close();
      const motionContext=await browser.newContext({viewport:{width:390,height:844},reducedMotion:'no-preference'});
      const motionPage=await motionContext.newPage();await motionPage.goto(url);
      await motionPage.locator('#motion-toggle').scrollIntoViewIfNeeded();
      const moving=await motionPage.locator('#swarm g').first().getAttribute('transform');
      await motionPage.waitForTimeout(150);
      assert.notEqual(await motionPage.locator('#swarm g').first().getAttribute('transform'),moving);
      await motionPage.locator('#motion-toggle').click();await motionPage.waitForTimeout(60);
      const paused=await motionPage.locator('#swarm g').first().getAttribute('transform');
      await motionPage.waitForTimeout(150);
      assert.equal(await motionPage.locator('#swarm g').first().getAttribute('transform'),paused);
      await motionPage.locator('#motion-toggle').click();await motionPage.waitForTimeout(150);
      assert.notEqual(await motionPage.locator('#swarm g').first().getAttribute('transform'),paused);
      await motionContext.close();check(`${name}: live Perlin motion pauses and resumes`);
    } finally {
      await browser.close();
    }
  }
} finally {
  await writeFile(
    `${out}/${engines[0][0]}-results.json`,
    JSON.stringify(results, null, 2),
  );
  await new Promise((done) => server.close(done));
}
