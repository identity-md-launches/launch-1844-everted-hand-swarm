import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve, extname } from "node:path";
const root = resolve(process.argv[2] || "dist");
const port = Number(process.argv[3] || 4173);
const mime = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css",
  ".js": "text/javascript",
  ".json": "application/json",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
};
createServer(async (req, res) => {
  let url;
  try {
    url = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
  } catch {
    res.writeHead(400).end();
    return;
  }
  if (url === "/simd-coin.json") {
    res.writeHead(200, { "Content-Type": "application/json" }).end("{}");
    return;
  }
  if (url.startsWith("/preview/")) url = url.slice("/preview".length);
  const path = resolve(
    root,
    "." + (url.endsWith("/") ? url + "index.html" : url),
  );
  if (!path.startsWith(root + "/")) {
    res.writeHead(403).end();
    return;
  }
  try {
    const body = await readFile(path);
    res
      .writeHead(200, {
        "Content-Type": mime[extname(path)] || "application/octet-stream",
      })
      .end(body);
  } catch {
    res
      .writeHead(404, { "Content-Type": "text/html" })
      .end(await readFile(resolve(root, "404.html")));
  }
}).listen(port, "0.0.0.0", () =>
  console.log(`Preview: http://localhost:${port}/preview/ (Ctrl+C to stop)`),
);
