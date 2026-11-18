import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const resource = file => readFileSync(new URL("../../App/Rendering/ZakkaArtwork.bundle/" + file, import.meta.url), "utf8");
const context = vm.createContext({});
vm.runInContext(resource("engine.js"), context);
const canvas = { width: 1200, height: 800, backgroundColor: "#fffdf7" };
const frame = { x: 10, y: 30, width: 350, height: 200, rotation: 12, opacity: 0.9, locked: false };
const plan = (layers, opts = {}) => JSON.parse(context.ZakkaArtwork.plan(JSON.stringify({
  version: 1, canvas: { ...canvas, ...opts.canvas },
  layers: layers.map((l, i) => ({ id: `layer-${i}`, ...frame, ...l })),
}), !!opts.editor, !!opts.thumb));

test("imported media and legacy washi share one authenticated asset; background uses storage ID", () => {
  const result = plan([
    { kind: "photo", assetId: "asset_nasa", fit: "cover", mask: { shape: "diamond", inset: 0, feather: 0 } },
    { kind: "washiTape", assetId: "asset_nasa", outline: "torn" },
    { kind: "sticker", stickerId: "custom:custom_sticker_moon" },
  ], { thumb: true, canvas: { background: { ...frame, backgroundId: "custom:custom_bg_a" } } });
  assert.equal(result.omitted, 0);
  assert.deepEqual(result.resources, [{ asset: "asset_nasa" }, { path: "/custom-stickers/custom_sticker_moon/content" },
    { path: "/custom-backgrounds/custom_bg_a/thumbnail" }]);
  assert.match(result.svg, /clipPath/);
  assert.equal(result.svg.match(/href="zakka-media:0"/g).length, 2);
  assert.match(result.svg, /viewBox="0 0 1200 800"/);
});

test("bundled WOFF becomes paths, legacy sticker becomes vector, and placeholders are editor-only", () => {
  const layers = [{ kind: "text", text: "Hello **moon**", fontFamily: "Love Ya Like A Sister",
    fontSize: 64, color: "#102030", align: "center" }, { kind: "photo", fit: "cover" },
    { kind: "sticker", stickerId: "heart" }];
  const result = plan(layers, { editor: true });
  assert.equal(result.omitted, 0);
  assert.match(result.svg, /<path /);
  assert.doesNotMatch(result.svg, /<text /);
  assert.match(result.svg, /data-photo-placeholder="true"/);
  assert.doesNotMatch(plan(layers).svg, /data-photo-placeholder="true"/);
});

test("unknown layers degrade individually; invalid canvas is not rendered", () => {
  const result = plan([{ kind: "future" }, { kind: "photo", assetId: "asset_a", fit: "contain" }]);
  assert.equal(result.omitted, 1);
  assert.deepEqual(result.resources, [{ asset: "asset_a" }]);
  assert.throws(() => plan([], { canvas: { width: -1 } }));
});

test("vector maps use Natural Earth; raster maps resolve only proxy tiles", () => {
  context.ZakkaArtwork.installWorld(resource("world-50m.topojson"));
  const map = { kind: "map", markers: [], routes: [] };
  const vector = plan([{ ...map, style: "atlas", highlightedCountries: ["USA"] }]);
  assert.equal(vector.omitted, 0);
  assert.ok(vector.svg.length > 10_000);
  assert.deepEqual(vector.resources, []);
  const raster = plan([{ ...map, style: "osm" }]);
  assert.ok(raster.resources.length > 0);
  for (const { path } of raster.resources) assert.match(path, /^\/map-tiles\/osm\/\d+\/\d+\/\d+$/);
});
