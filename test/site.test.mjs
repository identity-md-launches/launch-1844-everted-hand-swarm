import test from "node:test";
import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import {
  safeUrl,
  tokenAddress,
  marketNumber,
  chartEmbed,
} from "../site/data.js";
import { noise } from "../site/swarm.js";
import { dynamic, translations } from "../site/translations.js";

test("remote data cannot inject executable or malformed destinations", () => {
  for (const value of [
    "javascript:alert(1)",
    "data:text/html,x",
    "http://unsafe.example",
    "//example.com",
    "https://u:p@example.com",
    {},
    null,
  ])
    assert.equal(safeUrl(value), null);
  assert.equal(
    safeUrl("https://www.si-md.xyz/launchpad"),
    "https://www.si-md.xyz/launchpad",
  );
  assert.equal(tokenAddress("launching…"), null);
  assert.equal(tokenAddress("0x" + "0".repeat(40)), null);
  // The provided IMD pair is a real address; this is validation only, never the EHS address.
  assert.ok(tokenAddress("0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7"));
});
test("only real finite nonnegative market values appear, including zero", () => {
  for (const value of [null, undefined, "123", NaN, Infinity, -1])
    assert.equal(marketNumber(value), null);
  assert.equal(marketNumber(0), 0);
  assert.equal(marketNumber(0.0000003), 0.0000003);
});
test("chart allowlist checks hostname and preserves query parameters", () => {
  assert.equal(
    chartEmbed("https://dexscreener.com.evil.example/a", "dark"),
    null,
  );
  assert.equal(chartEmbed("https://example.com/a", "dark"), null);
  const url = new URL(
    chartEmbed("https://dexscreener.com/ethereum/a?foo=bar", "light"),
  );
  assert.equal(url.searchParams.get("embed"), "1");
  assert.equal(url.searchParams.get("foo"), "bar");
  assert.equal(url.searchParams.get("theme"), "light");
});
test("every static and dynamic string has both translations", async () => {
  const html = await readFile("site/index.html", "utf8");
  const keys = [...html.matchAll(/data-i18n(?:-alt)?="([^"]+)"/g)].map(
    (m) => m[1],
  );
  for (const lang of ["es", "zh"]) {
    for (const key of keys)
      assert.ok(translations[lang][key], `${lang}: ${key}`);
    for (const key of Object.keys(dynamic.en))
      assert.ok(dynamic[lang][key], `${lang} dynamic: ${key}`);
  }
});
test("noise is continuous and deterministic", () => {
  assert.equal(noise(1.4, 2.8), noise(1.4, 2.8));
  assert.ok(Math.abs(noise(1.99999, 3.2) - noise(2.00001, 3.2)) < 0.001);
});
test("both pages and all relative runtime assets exist in export", async () => {
  for (const page of ["index.html", "404.html"]) {
    const html = await readFile("dist/" + page, "utf8");
    for (const match of html.matchAll(/(?:src|href)="([^"#]+)(?:#[^"]*)?"/g)) {
      const path = match[1];
      if (path.startsWith("https:") || path === "./") continue;
      assert.ok((await stat("dist/" + path)).isFile(), path);
    }
  }
});
