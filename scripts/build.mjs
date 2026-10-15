import { cp, mkdir, readdir, readFile, stat, access, rm } from "node:fs/promises";
import { join } from "node:path";
// No compilation: site/ is itself a deployable, build-free static website.
await access("site/index.html");
await rm("dist", { recursive: true, force: true });
await mkdir("dist", { recursive: true });
await cp("site", "dist", { recursive: true });
let count = 0,
  bytes = 0;
async function check(dir) {
  for (const file of await readdir(dir)) {
    const path = join(dir, file),
      info = await stat(path);
    if (info.isDirectory()) await check(path);
    else {
      count++;
      bytes += info.size;
      if (/\.(html|css|js)$/.test(file)) {
        const source = await readFile(path, "utf8");
        if (/\b(?:src|href)=["']\/assets\//.test(source))
          throw new Error(`Root-relative asset: ${path}`);
      }
    }
  }
}
await check("dist");
console.log(
  `Static export: ${count} files, ${bytes} bytes. No bundler or runtime dependencies.`,
);
