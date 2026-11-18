import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { build } from "esbuild";
import { unpackTTF } from "./woff.mjs";

process.chdir(fileURLToPath(new URL(".", import.meta.url)));
const upstream = "https://github.com/JakeShirley/zakka.git";
const revision = "6ae854485ee69cc6b4bdbc10204a6099e0af3747";
const local = process.env.ZAKKA_SOURCE;
const repo = resolve(local || ".build/zakka.git");
const git = (...args) => execFileSync("git", args, { maxBuffer: 64 * 1024 * 1024 });
mkdirSync(".build", { recursive: true });
if (!local && !existsSync(repo)) {
  git("init", "--bare", repo);
}
try {
  git("-C", repo, "cat-file", "-e", `${revision}^{commit}`);
} catch (error) {
  if (local) throw error;
  git("-C", repo, "fetch", "--depth=1", upstream, revision);
}

// Archive a commit, never read dirty files or install/generate into the server checkout.
const archive = git("-C", repo, "archive", revision, "packages/editor-core/src",
  "packages/editor-core/vendor/fonts", "packages/editor-core/vendor/maps/world-50m.topojson");
execFileSync("tar", ["-xf", "-", "-C", ".build"], { input: archive });
const core = ".build/packages/editor-core";
const dest = "../App/Rendering/ZakkaArtwork.bundle";
mkdirSync(dest, { recursive: true });
const read = (file) => readFileSync(file, "utf8");
const notices = [`Zakka @zakka/editor-core, ${upstream} at ${revision}. Bundled for the Zakka native client.
Map geography: Natural Earth (public domain); https://www.naturalearthdata.com/.
Noto Emoji artwork: Google, Inc., https://github.com/googlefonts/noto-emoji (Apache License 2.0, text below).
Twemoji artwork: Twitter, Inc. and other contributors, https://github.com/jdecked/twemoji,
licensed under CC BY 4.0, https://creativecommons.org/licenses/by/4.0/.
Selected Iconify SVG paths reproduced at source viewBox, with fragment IDs namespaced.
Unicode fallback mapping is from the same Iconify sets.`];

const { googleFonts } = await import(pathToFileURL(resolve(core, "src/google-fonts.ts")));
// Imported book font aliases use upstream's open-source substitutes, not commercial files.
const included = new Set(["roboto-400", "roboto-700", "baskervville-400", "baskervville-400-italic",
  "baskervville-700", "love-ya-like-a-sister-400", "lato-400", "lato-700", "caveat-400",
  "dancing-script-400", "allura-400", "libre-baskerville-400", "roboto-slab-400"]);
const fonts = googleFonts.filter(f => included.has(basename(f.vendorPath, ".woff")));
const fontMap = Object.fromEntries([...new Set(fonts.map(f => f.vendorPath))].map(path =>
  [path, readFileSync(`${core}/${path}`).toString("base64")]));
for (const name of ["lato-400", "baskervville-400"]) {
  writeFileSync(`${dest}/${name}.ttf`, unpackTTF(readFileSync(`${core}/vendor/fonts/google-fonts/${name}.woff`)));
}
mkdirSync(`${core}/src/generated`, { recursive: true });
writeFileSync(`${core}/src/google-fonts.ts`, `export const googleFonts=${JSON.stringify(fonts)};`);
writeFileSync(`${core}/src/generated/googleFonts.ts`,
  `export const googleFontBase64ByVendorPath=${JSON.stringify(fontMap)};`);
writeFileSync(".build/opentype.mjs",
  `import { parse } from "../node_modules/opentype.js/dist/opentype.mjs"; export default { parse };`);
for (const family of [...new Set(fonts.map(f => f.googleFamily))].sort()) {
  notices.push(`${family} — bundled WOFF\n${read(`${core}/vendor/fonts/google-fonts/licenses/${family.toLowerCase().replace(/[^a-z0-9]+/g, "-")}.txt`)}`);
}

const common = ["red-heart", "star", "camera", "cupcake", "blossom", "paperclip", "balloon",
  "rainbow", "sparkles", "sun-with-face", "airplane", "birthday-cake", "party-popper",
  "smiling-face-with-smiling-eyes", "beach-with-umbrella", "palm-tree", "wrapped-gift", "snowflake"];
const glyphs = {}, stickers = {};
for (const lib of ["noto", "twemoji"]) {
  const dir = `node_modules/@iconify-json/${lib}`;
  const set = JSON.parse(read(`${dir}/icons.json`));
  for (const name of common) {
    const icon = set.icons[name];
    if (icon) stickers[`${lib}:${name}`] = { viewBox: `0 0 ${icon.width || set.width || 16} ${icon.height || set.height || 16}`, body: icon.body };
  }
  for (const [seq, name] of Object.entries(JSON.parse(read(`${dir}/chars.json`)))) {
    if (/^[0-9a-f]+(-[0-9a-f]+)*$/i.test(seq)) {
      glyphs[`${lib}:${name}`] = String.fromCodePoint(...seq.split("-").map(n => parseInt(n, 16)));
    }
  }
}
writeFileSync(".build/stickers.json", JSON.stringify({ stickers, glyphs }));
copyFileSync(`${core}/vendor/maps/world-50m.topojson`, `${dest}/world-50m.topojson`);

await build({
  entryPoints: ["bridge.ts"], outfile: `${dest}/engine.js`, bundle: true, minify: true,
  format: "iife", globalName: "ZakkaArtwork", target: "es2022", platform: "browser",
  // Do not select opentype's dev-server browser wrapper.
  alias: { "opentype.js": resolve(".build/opentype.mjs") },
  legalComments: "inline",
});
for (const pkg of ["d3-array", "d3-geo", "internmap", "marked", "opentype.js", "tiny-inflate", "topojson-client", "zod"]) {
  notices.push(`${pkg}\n${read(`node_modules/${pkg}/LICENSE`)}`);
}
writeFileSync(`${dest}/Acknowledgements.txt`, notices.join("\n\n" + "=".repeat(74) + "\n\n"));
console.log(`Built editor-core ${revision}; ${fonts.length} font aliases, ${Object.keys(stickers).length} SVG stickers.`);
