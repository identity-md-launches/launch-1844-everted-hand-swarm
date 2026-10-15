import { dynamic, translations } from "./translations.js";
const root = document.documentElement;
const select = /** @type {HTMLSelectElement} */ (
  document.querySelector("#error-language")
);
let language = "en";
try {
  language = localStorage.getItem("ehs-language") || "en";
} catch {
  /* optional preference */
}
if (!["en", "es", "zh"].includes(language)) language = "en";
function render() {
  select.value = language;
  root.lang = language === "zh" ? "zh-CN" : language;
  document.querySelector("#error-title").textContent =
    dynamic[language].errorTitle;
  document.querySelector("#error-copy").textContent =
    dynamic[language].errorCopy;
  document.querySelector("#error-back").textContent =
    dynamic[language].errorBack;
  document.querySelector("label").textContent =
    language === "en" ? "Language" : translations[language].language;
  document
    .querySelector("#error-theme")
    .setAttribute(
      "aria-label",
      dynamic[language][root.dataset.theme === "dark" ? "light" : "dark"],
    );
  document.title = dynamic[language].errorTitle + " · Everted Hand Swarm";
  const footer = document.querySelector(".site-footer p");
  const built =
    language === "en"
      ? "Built 100% by the Identity.md swarm"
      : translations[language].footerBuilt;
  const launched =
    language === "en" ? "launched on" : translations[language].footerLaunched;
  const advice =
    language === "en"
      ? "not financial advice"
      : translations[language].footerAdvice;
  footer.replaceChildren(document.createTextNode(`${built} · ${launched} `));
  const link = document.createElement("a");
  link.href = "https://www.si-md.xyz/launchpad";
  link.textContent = "si-md.xyz/launchpad";
  footer.append(link, document.createTextNode(` · ${advice}`));
  document
    .querySelector(".error-content img")
    .setAttribute(
      "alt",
      language === "en"
        ? "A hand branching into smaller hands."
        : translations[language].heroLogoAlt,
    );
}
select.addEventListener("change", () => {
  language = select.value;
  try {
    localStorage.setItem("ehs-language", language);
  } catch {}
  render();
});
document.querySelector("#error-theme").addEventListener("click", () => {
  root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
  try {
    localStorage.setItem("ehs-theme", root.dataset.theme);
  } catch {}
  render();
});
render();
