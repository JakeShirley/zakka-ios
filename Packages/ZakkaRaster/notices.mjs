import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync, writeFileSync, copyFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

// Called in the extracted resvg workspace by build.sh. Use the actual linked feature graph,
// not the much larger workspace lockfile (CLI, benchmarks, test-only codecs, etc.).
const [rust, flags, output] = process.argv.slice(2);
const run = (tool, args) => execFileSync(tool, args, { encoding: "utf8", maxBuffer: 8 * 1024 * 1024 });
const cargo = (...args) => run("cargo", [`+${rust}`, ...args]);
const packages = JSON.parse(cargo("metadata", "--locked", "--format-version", "1")).packages;
const selected = new Set(cargo("tree", "--locked", "-p", "resvg-capi", "--target", "aarch64-apple-ios",
  "--no-default-features", "--features", flags, "-e", "normal", "--prefix", "none", "--format", "{p}")
  .split("\n").map(line => line.split(" ").slice(0, 2).join(" ")));
const texts = new Map();
const add = (title, text) => {
  const contents = text.trim();
  texts.set(contents, [...(texts.get(contents) ?? []), title]);
};
const index = [];
for (const pkg of packages.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : a.version.localeCompare(b.version))) {
  const title = `${pkg.name} v${pkg.version}`;
  if (!selected.has(title)) continue;
  index.push(`${title}: ${pkg.license}`);
  const root = pkg.source ? dirname(pkg.manifest_path) : resolve(".");
  const files = readdirSync(root, { withFileTypes: true })
    .filter(f => f.isFile() && /^(license|copying|copyright|notice|authors)/i.test(f.name)).map(f => f.name).sort();
  if (!files.length) {
    if (!["zune-jpeg", "zune-core"].includes(pkg.name)) throw Error(`Missing license: ${title}`);
    // The .crate has a copyright/grant in lib.rs but no root license file.
    const text = readFileSync(join(root, "src/lib.rs"), "utf8").split("*/")[0] + "*/";
    add(title, `${pkg.authors.join(", ")}\n${text}\nThe Apache 2.0 option is used (license text included below).`);
  }
  for (const f of files) add(`${title} — ${f}`, readFileSync(join(root, f), "utf8"));
}
const header = `resvg 0.45.1, https://github.com/linebender/resvg at 1b6c2fddbcbeffa8135df4323b02aaae84890907.
Modification: the C option constructor disables filesystem image resolution; see data-only.patch.
Compiled with Rust ${rust}. Standard library notices: Rust-LICENSE.html.
The following licenses and notices apply to components of the static library.\n\n`;
writeFileSync(join(output, "Resvg-LICENSES.txt"), header + index.join("\n") + "\n\n" +
  [...texts.entries()].map(([text, titles]) => titles.join("\n") + "\n\n" + text).join("\n\n----------------------------------------\n\n") + "\n");
const sysroot = run("rustc", [`+${rust}`, "--print", "sysroot"]).trim();
copyFileSync(join(sysroot, "share/doc/rust/COPYRIGHT-library.html"), join(output, "Rust-LICENSE.html"));
