import { inflateSync } from "node:zlib";

// Undo the WOFF 1 container: preserve the font's original tables, including names and hints.
export function unpackTTF(woff) {
  if (woff.toString("ascii", 0, 4) !== "wOFF" || woff.readUInt32BE(4) !== 0x10000) throw Error("Expected WOFF1 TrueType");
  const count = woff.readUInt16BE(12);
  const result = Buffer.alloc(woff.readUInt32BE(16));
  const log = Math.floor(Math.log2(count));
  result.writeUInt32BE(0x10000);
  result.writeUInt16BE(count, 4);
  result.writeUInt16BE(16 << log, 6);
  result.writeUInt16BE(log, 8);
  result.writeUInt16BE(count * 16 - (16 << log), 10);
  let pos = 12 + count * 16, head = 0;
  for (let i = 0; i < count; i++) {
    const row = 44 + i * 20, dir = 12 + i * 16;
    const offset = woff.readUInt32BE(row + 4), compressed = woff.readUInt32BE(row + 8), length = woff.readUInt32BE(row + 12);
    const bytes = woff.subarray(offset, offset + compressed);
    const table = compressed === length ? bytes : inflateSync(bytes);
    if (table.length !== length) throw Error("Invalid WOFF table");
    woff.copy(result, dir, row, row + 4);
    result.writeUInt32BE(woff.readUInt32BE(row + 16), dir + 4);
    result.writeUInt32BE(pos, dir + 8);
    result.writeUInt32BE(length, dir + 12);
    table.copy(result, pos);
    if (woff.toString("ascii", row, row + 4) === "head") head = pos;
    pos += (length + 3) & ~3;
  }
  if (!head || pos !== result.length) throw Error("Invalid SFNT directory");
  result.writeUInt32BE(0, head + 8);
  let checksum = 0;
  for (let i = 0; i < result.length; i += 4) checksum = (checksum + result.readUInt32BE(i)) >>> 0;
  result.writeUInt32BE((0xb1b0afba - checksum) >>> 0, head + 8);
  return result;
}
