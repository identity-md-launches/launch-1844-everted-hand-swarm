// Run before CSS paints so the saved appearance does not flash on load.
(() => {
  let saved = null;
  try {
    saved = localStorage.getItem("ehs-theme");
  } catch {
    /* private storage remains optional */
  }
  document.documentElement.dataset.theme =
    saved === "light" || saved === "dark"
      ? saved
      : matchMedia("(prefers-color-scheme: dark)").matches
        ? "dark"
        : "light";
})();
