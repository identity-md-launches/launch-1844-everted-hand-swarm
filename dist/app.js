import { dynamic, translations } from "./translations.js";
import { safeUrl, tokenAddress, marketNumber, chartEmbed } from "./data.js";
import { createSwarm } from "./swarm.js";
import { community } from "./config.js";

const $ = (selector) =>
  /** @type {HTMLElement} */ (document.querySelector(selector));
const root = document.documentElement;
const languageSelect = /** @type {HTMLSelectElement} */ ($("#language"));
const original = {};
document.querySelectorAll("[data-i18n]").forEach((el) => {
  original[el.getAttribute("data-i18n")] = el.innerHTML;
});
document.querySelectorAll("[data-i18n-alt]").forEach((el) => {
  original[el.getAttribute("data-i18n-alt")] = el.getAttribute("alt");
});
const readStorage = (key) => {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
};
const saveStorage = (key, value) => {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* preferences are optional */
  }
};
let language =
  readStorage("ehs-language") ||
  (navigator.language.startsWith("es")
    ? "es"
    : navigator.language.startsWith("zh")
      ? "zh"
      : "en");
if (!["en", "es", "zh"].includes(language)) language = "en";
const t = (key) =>
  dynamic[language][key] ??
  translations[language]?.[key] ??
  original[key] ??
  key;
const siteUrl = "https://evertedhandswarm.si-md.xyz/";
let lastData = null,
  requestRunning = false,
  hasMarket = false,
  failed = false,
  chartLoaded = false,
  activeStep = 0;
let swarm;

function setLanguage(next) {
  language = next;
  root.lang = next === "zh" ? "zh-CN" : next;
  languageSelect.value = next;
  saveStorage("ehs-language", next);
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    // Only checked-in translation strings enter markup. Remote data always uses textContent.
    el.innerHTML = translations[next]?.[key] ?? original[key];
  });
  document
    .querySelectorAll("[data-i18n-alt]")
    .forEach((el) =>
      el.setAttribute(
        "alt",
        translations[next]?.[el.getAttribute("data-i18n-alt")] ??
          original[el.getAttribute("data-i18n-alt")],
      ),
    );
  $("#theme-toggle").setAttribute(
    "aria-label",
    t(root.dataset.theme === "dark" ? "light" : "dark"),
  );
  $("#menu-toggle").setAttribute(
    "aria-label",
    t(
      $("#navigation").classList.contains("is-open") ? "menuClose" : "menuOpen",
    ),
  );
  $("#navigation").setAttribute("aria-label", t("navigation"));
  $("#playground").setAttribute("aria-label", t("playground"));
  $("#logo-sticker").setAttribute("aria-label", t("logoAction"));
  $("#reset-swarm").setAttribute("aria-label", t("reset"));
  $(".step-tabs").setAttribute("aria-label", t("steps"));
  document
    .querySelectorAll(".marquee-track span")
    .forEach((el) => (el.textContent = `$EHS ✳ ${t("tagline")} ✳ `));
  $("#share-status").textContent = "";
  $("#contract-status").textContent = "";
  for (let i = 0; i < 3; i++) {
    const url = new URL("https://x.com/intent/tweet");
    url.searchParams.set("text", t("shareTexts")[i]);
    url.searchParams.set("url", siteUrl);
    $(`#share-${i + 1}`).setAttribute("href", url.href);
  }
  const telegram = new URL("https://t.me/share/url");
  telegram.searchParams.set("url", siteUrl);
  telegram.searchParams.set("text", t("shareTexts")[0]);
  $("#share-telegram").setAttribute("href", telegram.href);
  setStep(activeStep);
  renderData(lastData);
  swarm?.translate();
}
languageSelect.addEventListener("change", () =>
  setLanguage(languageSelect.value),
);

function closeMenu(returnFocus = false) {
  $("#navigation").classList.remove("is-open");
  $("#menu-toggle").setAttribute("aria-expanded", "false");
  $("#menu-toggle").setAttribute("aria-label", t("menuOpen"));
  if (returnFocus) $("#menu-toggle").focus();
}
$("#menu-toggle").addEventListener("click", () => {
  const open = $("#navigation").classList.toggle("is-open");
  $("#menu-toggle").setAttribute("aria-expanded", String(open));
  $("#menu-toggle").setAttribute(
    "aria-label",
    t(open ? "menuClose" : "menuOpen"),
  );
});
$("#navigation")
  .querySelectorAll("a")
  .forEach((a) => a.addEventListener("click", () => closeMenu()));
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && $("#navigation").classList.contains("is-open"))
    closeMenu(true);
});
document.addEventListener("click", (event) => {
  if (!(/** @type {Element} */ (event.target).closest(".site-header")))
    closeMenu();
});

function changeTheme(theme) {
  root.classList.add("no-transitions");
  root.dataset.theme = theme;
  $("#theme-toggle").setAttribute(
    "aria-label",
    t(theme === "dark" ? "light" : "dark"),
  );
  document
    .querySelector('meta[name="theme-color"]')
    .setAttribute("content", theme === "dark" ? "#0c0c0c" : "#e7e1df");
  if (chartLoaded) loadChart();
  void root.offsetHeight;
  requestAnimationFrame(() => root.classList.remove("no-transitions"));
}
$("#theme-toggle").addEventListener("click", () => {
  const theme = root.dataset.theme === "dark" ? "light" : "dark";
  saveStorage("ehs-theme", theme);
  changeTheme(theme);
});
matchMedia("(prefers-color-scheme: dark)").addEventListener(
  "change",
  (event) => {
    if (!readStorage("ehs-theme"))
      changeTheme(event.matches ? "dark" : "light");
  },
);

function setStep(index, focus = false) {
  activeStep = index;
  document.querySelectorAll("[data-step]").forEach((tab, i) => {
    tab.setAttribute("aria-selected", String(i === index));
    tab.setAttribute("tabindex", i === index ? "0" : "-1");
    $(`#step-${i + 1}`).hidden = i !== index;
    if (focus && i === index) /** @type {HTMLElement} */ (tab).focus();
  });
  $("#step-progress").textContent = `${index + 1} / 3`;
  $("#next-step").textContent = t(index === 2 ? "first" : "next");
}
document.querySelectorAll("[data-step]").forEach((tab, index) => {
  tab.addEventListener("click", () => setStep(index));
  tab.addEventListener("keydown", (event) => {
    const e = /** @type {KeyboardEvent} */ (event);
    const keys = {
      ArrowRight: (index + 1) % 3,
      ArrowLeft: (index + 2) % 3,
      Home: 0,
      End: 2,
    };
    if (e.key in keys) {
      e.preventDefault();
      setStep(keys[e.key], true);
    }
  });
});
$("#next-step").addEventListener("click", () => setStep((activeStep + 1) % 3));

async function copy(value, status, source) {
  try {
    if (!navigator.clipboard) throw new Error("Clipboard unavailable");
    await navigator.clipboard.writeText(value);
    status.textContent = t("copied");
  } catch {
    status.textContent = t("copyFailed");
    if (source) {
      const range = document.createRange();
      range.selectNodeContents(source);
      const selection = getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    } else status.textContent += ` ${value}`;
  }
}
$("#copy-link").addEventListener("click", () =>
  copy(siteUrl, $("#share-status"), null),
);
$("#copy-contract").addEventListener("click", () => {
  const address = tokenAddress(lastData?.token);
  if (address) copy(address, $("#contract-status"), $("#contract-address"));
});

function animateNumber(el, value, price) {
  const locale = language === "zh" ? "zh-CN" : language;
  const format = (number) =>
    new Intl.NumberFormat(locale, {
      style: "currency",
      currency: "USD",
      notation: price ? "standard" : "compact",
      maximumFractionDigits: price ? (number < 0.01 ? 10 : 4) : 2,
    }).format(number);
  const previous = Number(el.dataset.value);
  el.dataset.value = String(value);
  if (
    !Number.isFinite(previous) ||
    matchMedia("(prefers-reduced-motion: reduce)").matches ||
    root.dataset.motion === "paused" ||
    previous === value
  ) {
    el.textContent = format(value);
    return;
  }
  let start;
  const frame = (time) => {
    if (Number(el.dataset.value) !== value) return;
    start ??= time;
    const progress = Math.min((time - start) / 500, 1);
    el.textContent = format(
      previous + (value - previous) * (1 - (1 - progress) ** 3),
    );
    if (progress < 1) requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

function renderData(data) {
  const token = tokenAddress(data?.token),
    coin = safeUrl(data?.coinUrl),
    chart = safeUrl(data?.chartUrl);
  $("#contract-address").textContent = token || t("launching");
  /** @type {HTMLButtonElement} */ ($("#copy-contract")).disabled = !token;
  $("#launch-status").textContent = token ? t("live") : t("launching");
  document.querySelectorAll(".buy-link").forEach((a) => {
    a.setAttribute("href", coin || "#buy");
    if (coin) {
      a.setAttribute("target", "_blank");
      a.setAttribute("rel", "noopener noreferrer");
    } else a.removeAttribute("target");
  });
  document.querySelectorAll(".chart-link").forEach((a) => {
    a.setAttribute("href", chart || "#chart");
    if (chart) {
      a.setAttribute("target", "_blank");
      a.setAttribute("rel", "noopener noreferrer");
    } else a.removeAttribute("target");
  });
  $("#buy-availability").textContent = t(coin ? "available" : "buyWaiting");
  const logo = safeUrl(data?.logo);
  const hero = /** @type {HTMLImageElement} */ ($("#hero-logo"));
  if (logo && hero.dataset.logo !== logo) {
    hero.dataset.logo = logo;
    hero.src = logo;
    document
      .querySelector('meta[property="og:image"]')
      .setAttribute("content", logo);
    document
      .querySelector('meta[name="twitter:image"]')
      .setAttribute("content", logo);
  }
  hasMarket = false;
  [
    ["priceUsd", "price-value"],
    ["marketCap", "cap-value"],
    ["volume24h", "volume-value"],
  ].forEach(([field, id]) => {
    const value = marketNumber(data?.market?.[field]);
    $(`[data-stat="${field}"]`).hidden = value === null;
    if (value !== null) {
      hasMarket = true;
      animateNumber($("#" + id), value, field === "priceUsd");
    }
  });
  $("#stats").hidden = !hasMarket;
  $("#data-status").textContent = t(
    failed
      ? hasMarket
        ? "dataStale"
        : "dataError"
      : hasMarket
        ? "dataLive"
        : "dataWaiting",
  );
  const embed = chartEmbed(chart, root.dataset.theme);
  $("#chart-panel").hidden = !embed;
  $("#external-chart").hidden = !chart;
  if (chart) $("#external-chart").setAttribute("href", chart);
  if (!embed) {
    $("#chart-frame").replaceChildren();
    chartLoaded = false;
    $(".chart-consent").hidden = false;
    $("#chart-fallback").hidden = true;
  } else if (chartLoaded) loadChart();
  const socials = {
    x: safeUrl(data?.socials?.x) || safeUrl(community.x),
    telegram: safeUrl(data?.socials?.telegram) || safeUrl(community.telegram),
  };
  let anySocial = false;
  for (const [name, url] of Object.entries(socials)) {
    const link = $(`#social-${name}`);
    link.hidden = !url;
    if (url) {
      link.setAttribute("href", url);
      anySocial = true;
    }
  }
  $("#social-note").textContent = t(
    anySocial ? "socialPartial" : "socialPending",
  );
}
$("#hero-logo").addEventListener("error", () => {
  const image = /** @type {HTMLImageElement} */ ($("#hero-logo"));
  if (!image.src.endsWith("/assets/logo.jpg")) image.src = "assets/logo.jpg";
});

async function refresh() {
  if (requestRunning) return;
  requestRunning = true;
  $("#refresh-stats").setAttribute("aria-busy", "true");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 7000);
  try {
    const response = await fetch("/simd-coin.json", {
      cache: "no-store",
      signal: controller.signal,
      credentials: "same-origin",
    });
    if (!response.ok) throw new Error("Live data unavailable");
    const data = await response.json();
    if (!data || typeof data !== "object" || Array.isArray(data))
      throw new Error("Invalid live data");
    lastData = data;
    failed = false;
    renderData(data);
  } catch {
    failed = true;
    renderData(lastData);
  } finally {
    clearTimeout(timeout);
    requestRunning = false;
    $("#refresh-stats").removeAttribute("aria-busy");
  }
}
$("#refresh-stats").addEventListener("click", refresh);
setInterval(() => {
  if (!document.hidden) refresh();
}, 30000);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) refresh();
});

function loadChart() {
  const url = chartEmbed(lastData?.chartUrl, root.dataset.theme);
  if (!url) return;
  const existing = $("#chart-frame iframe");
  if (existing?.getAttribute("src") === url) {
    existing.setAttribute("title", t("chartTitle"));
    return;
  }
  const iframe = document.createElement("iframe");
  iframe.title = t("chartTitle");
  iframe.loading = "lazy";
  iframe.referrerPolicy = "no-referrer";
  iframe.setAttribute(
    "sandbox",
    "allow-scripts allow-same-origin allow-popups",
  );
  iframe.src = url;
  $("#chart-frame").replaceChildren(iframe);
  chartLoaded = true;
  $(".chart-consent").hidden = true;
  $("#chart-fallback").hidden = false;
}
$("#load-chart").addEventListener("click", loadChart);

document.querySelectorAll(".buy-link").forEach((a) =>
  a.addEventListener("click", (event) => {
    if (
      matchMedia("(prefers-reduced-motion: reduce)").matches ||
      root.dataset.motion === "paused"
    )
      return;
    const e = /** @type {MouseEvent} */ (event),
      box = a.getBoundingClientRect();
    const x = e.clientX || box.left + box.width / 2,
      y = e.clientY || box.top + box.height / 2;
    for (let i = 0; i < 10; i++) {
      const bit = document.createElement("span");
      bit.className = "confetti";
      bit.setAttribute("aria-hidden", "true");
      bit.style.left = x + "px";
      bit.style.top = y + "px";
      bit.style.setProperty("--cx", `${Math.cos(i * 2.399) * 65}px`);
      bit.style.setProperty("--cy", `${Math.sin(i * 2.399) * 65 - 30}px`);
      document.body.append(bit);
      setTimeout(() => bit.remove(), 700);
    }
  }),
);
setLanguage(language);
swarm = createSwarm(t);
changeTheme(root.dataset.theme);
refresh();
