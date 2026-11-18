import { renderPageDocumentSvg, getCustomBackgroundStorageId, builtInBackgroundIdPrefix,
  isCustomStickerId, pageLayerSchema } from "./.build/packages/editor-core/src/index.js";
import { decodeMapGeography } from "./.build/packages/editor-core/src/map-geography.js";
import catalog from "./.build/stickers.json";

let geography: ReturnType<typeof decodeMapGeography>;
export function installWorld(topology: string) { geography = decodeMapGeography(topology, "low"); }

// JavaScriptCore lacks the DOM's atob. This is only used to read trusted bundled WOFF.
globalThis.atob ??= (encoded: string): string => {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let out = "", bits = 0, acc = 0;
  for (const c of encoded) {
    if (c === "=") break;
    acc = (acc << 6) | chars.indexOf(c); bits += 6;
    if (bits >= 8) { bits -= 8; out += String.fromCharCode((acc >> bits) & 255); }
  }
  return out;
};

// IDs supplied by documents are path components, never arbitrary requests.
const safeID = (id: string | undefined) => id && /^[a-zA-Z0-9_-]+$/.test(id) ? id : null;

export function plan(json: string, editor: boolean, thumbnail: boolean): string {
  const resources: { asset?: string; path?: string; glyph?: string }[] = [];
  const indices = new Map<string, number>();
  const href = (kind: "asset" | "path" | "glyph", value: string | null | undefined) => {
    if (!value) return null;
    const key = `${kind}:${value}`;
    if (!indices.has(key)) {
      indices.set(key, resources.length);
      resources.push({ [kind]: value });
    }
    return `zakka-media:${indices.get(key)}`;
  };
  let iconIndex = 0;
  const document = JSON.parse(json);
  const render = () => renderPageDocumentSvg(document, {
    showPhotoPlaceholders: editor, showTextPlaceholders: editor,
    resolvePhotoHref: l => href("asset", safeID(l.assetId)),
    resolveWashiTapeHref: l => href("asset", safeID(l.pattern.assetId ?? l.assetId)),
    resolveMapGeography: () => geography,
    resolveMapTileHref: t => href("path", `/map-tiles/${t.provider}/${t.z}/${t.x}/${t.y}`),
    resolveBackgroundHref: b => {
      const variant = thumbnail ? "thumbnail" : "content";
      const custom = getCustomBackgroundStorageId(b.backgroundId);
      if (custom) return href("path", safeID(custom) && `/custom-backgrounds/${custom}/${variant}`);
      const slug = safeID(b.backgroundId.slice(builtInBackgroundIdPrefix.length));
      return href("path", slug && `/backgrounds/builtin/${slug}/${variant}`);
    },
    resolveStickerHref: l => isCustomStickerId(l.stickerId)
      ? href("path", `/custom-stickers/${l.stickerId.slice("custom:".length)}/content`)
      : !catalog.stickers[l.stickerId] ? href("glyph", catalog.glyphs[l.stickerId]) : null,
    resolveStickerSvg: l => {
      const icon = catalog.stickers[l.stickerId];
      if (icon) {
        const prefix = `zkIcon${iconIndex++}_`;
        const ids = new Set(Array.from(icon.body.matchAll(/\bid="([^"]+)"/g), m => m[1]));
        return { viewBox: icon.viewBox, body: icon.body
          .replace(/\bid="([^"]+)"/g, (_, id) => `id="${prefix}${id}"`)
          .replace(/#([\w:-]+)/g, (original, id) => ids.has(id) ? `#${prefix}${id}` : original) };
      }
      return null;
    },
  });
  let svg: string, omitted = 0;
  try { svg = render(); }
  catch (error) {
    // Keep an unreadable layer from hiding an otherwise usable book. Do not repair or
    // mutate the source document; tell the view we're showing a partial preview.
    if (error?.name !== "ZodError" || !Array.isArray(document.layers) || document.layers.length > 200) throw error;
    const valid = document.layers.filter(l => pageLayerSchema.safeParse(l).success);
    omitted = document.layers.length - valid.length;
    if (!omitted) throw error;
    document.layers = valid;
    svg = render();
  }
  return JSON.stringify({ svg, resources, omitted });
}
