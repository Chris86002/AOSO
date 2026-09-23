// Original, deterministic UI2 frame artwork. Run: node tools/build-ui2-frames.cjs
// No dependencies. Keep live text, telemetry, pippers and topology in KerboScript.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = path.join(__dirname, '../AOSO/ux/ui2_assets');
const ink = [0, 145, 83, 255];
const dim = [18, 71, 52, 255];
const background = [6, 14, 15, 255];

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, bytes) {
  const tag = Buffer.from(type);
  const size = Buffer.alloc(4);
  size.writeUInt32BE(bytes.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([tag, bytes])));
  return Buffer.concat([size, tag, bytes, checksum]);
}
function frame(name, height, draw) {
  const width = 420;
  const pixels = Buffer.alloc(width * height * 4);
  for (let i = 0; i < pixels.length; i += 4) pixels.set(background, i);
  const line = (x1, y1, x2, y2, color = dim) => {
    const steps = Math.max(Math.abs(x2 - x1), Math.abs(y2 - y1), 1);
    for (let i = 0; i <= steps; i++) {
      const x = Math.round(x1 + (x2 - x1) * i / steps);
      const y = Math.round(y1 + (y2 - y1) * i / steps);
      if (x >= 0 && x < width && y >= 0 && y < height) pixels.set(color, (y * width + x) * 4);
    }
  };
  const rect = (x1, y1, x2, y2, color = ink) => {
    line(x1, y1, x2, y1, color); line(x2, y1, x2, y2, color);
    line(x2, y2, x1, y2, color); line(x1, y2, x1, y1, color);
  };
  rect(1, 1, 418, height - 2);
  draw(line, rect);
  const rows = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) pixels.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 6; // 8-bit RGBA, non-interlaced, filter 0 rows
  fs.writeFileSync(path.join(root, name + '.png'), Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(rows, {level: 9})), chunk('IEND', Buffer.alloc(0)),
  ]));
  console.log(`${name}.png: ${width} x ${height}`);
}

frame('pfd_frame', 250, (line, rect) => {
  rect(78, 24, 326, 226, dim);
  line(92, 125, 312, 125, ink);
  for (const y of [65, 95, 155, 185]) {
    const half = (y === 95 || y === 155) ? 30 : 48;
    line(210 - half, y, 204, y); line(216, y, 210 + half, y);
  }
  // Fixed reference marks only: the movable guidance diamond is a live widget.
  for (let y = 45; y <= 205; y += 20) {
    line(68, y, 76, y); line(328, y, 336, y);
  }
  line(198, 125, 204, 131, ink); line(204, 131, 210, 125, ink);
  line(210, 125, 216, 131, ink); line(216, 131, 222, 125, ink);
});
// Quiet backgrounds leave room for dynamic route, system and topology widgets.
frame('mission_frame', 180, () => {});
frame('systems_frame', 180, () => {});
frame('twin_frame', 250, () => {});
frame('vehicle_frame', 250, () => {}); // legacy asset retained at its original size
frame('descent_frame', 120, (line) => {
  line(38, 12, 38, 108, ink);
  for (let y = 18; y <= 102; y += 12) line(38, y, 48, y);
  line(16, 108, 403, 108);
});
