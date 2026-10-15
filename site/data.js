/** Accept HTTPS destinations only; never turn remote data into markup or executable URLs. */
export function safeUrl(value) {
  if (typeof value !== "string" || !value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password
      ? url.href
      : null;
  } catch {
    return null;
  }
}
export function tokenAddress(value) {
  return typeof value === "string" &&
    /^0x[0-9a-fA-F]{40}$/.test(value) &&
    !/^0x0{40}$/.test(value)
    ? value
    : null;
}
export function marketNumber(value) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? value
    : null;
}
export function chartEmbed(value, theme) {
  const valid = safeUrl(value);
  if (!valid) return null;
  const url = new URL(valid);
  if (
    url.hostname !== "dexscreener.com" &&
    url.hostname !== "www.dexscreener.com"
  )
    return null;
  url.searchParams.set("embed", "1");
  url.searchParams.set("theme", theme === "light" ? "light" : "dark");
  url.searchParams.set("trades", "0");
  url.searchParams.set("info", "0");
  return url.href;
}
