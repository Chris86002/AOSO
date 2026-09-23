// Original AOSO cockpit art, informed by OPS3's dense instrument layout.
// Rebuild with: node tools/build-ui2-frames.cjs (no external packages).
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = path.join(__dirname, '../AOSO/ux/ui2_assets');
const rgb = (r, g, b) => [r, g, b, 255];
const C = {
  black: rgb(4, 8, 9), floor: rgb(15, 23, 25), bezel: rgb(57, 67, 72),
  edge: rgb(102, 116, 121), grid: rgb(23, 63, 44), gridHi: rgb(31, 102, 60),
  green: rgb(26, 240, 52), muted: rgb(37, 142, 67), amber: rgb(226, 184, 40),
  red: rgb(206, 44, 44),
};
function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, bytes) {
  const tag = Buffer.from(type), size = Buffer.alloc(4), checksum = Buffer.alloc(4);
  size.writeUInt32BE(bytes.length);
  checksum.writeUInt32BE(crc32(Buffer.concat([tag, bytes])));
  return Buffer.concat([size, tag, bytes, checksum]);
}
function image(name, width, height, draw, panel = true) {
  const pixels = Buffer.alloc(width * height * 4);
  const put = (x, y, color) => {
    x = Math.round(x); y = Math.round(y);
    if (x >= 0 && x < width && y >= 0 && y < height) pixels.set(color, (y * width + x) * 4);
  };
  const fill = (x1, y1, x2, y2, color) => {
    for (let y = Math.max(0, y1); y <= Math.min(height - 1, y2); y++)
      for (let x = Math.max(0, x1); x <= Math.min(width - 1, x2); x++) put(x, y, color);
  };
  const line = (x1, y1, x2, y2, color = C.grid) => {
    const steps = Math.max(Math.abs(x2 - x1), Math.abs(y2 - y1), 1);
    for (let i = 0; i <= steps; i++) put(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, color);
  };
  const rect = (x1, y1, x2, y2, color = C.grid) => {
    line(x1, y1, x2, y1, color); line(x2, y1, x2, y2, color);
    line(x2, y2, x1, y2, color); line(x1, y2, x1, y1, color);
  };
  const ellipse = (cx, cy, rx, ry, color = C.grid) => {
    for (let i = 0; i < 720; i++) {
      const angle = i * Math.PI / 360;
      put(cx + Math.cos(angle) * rx, cy + Math.sin(angle) * ry, color);
    }
  };
  if (panel === true) {
    fill(0, 0, width - 1, height - 1, C.bezel);
    fill(3, 3, width - 4, height - 4, C.black);
    for (let y = 8; y < height - 8; y++) {
      for (let x = 8; x < width - 8; x++) {
        const radial = Math.max(0, 1 - Math.hypot((x - width / 2) / (width * .7), (y - height / 2) / (height * .8)));
        const v = Math.round(15 + 10 * radial);
        put(x, y, rgb(v, v + 7, v + 8));
      }
    }
    line(8, 8, width - 9, 8, C.edge); line(8, 8, 8, height - 9, C.edge);
    line(8, height - 9, width - 9, height - 9, C.bezel);
    line(width - 9, 8, width - 9, height - 9, C.bezel);
    for (const x of [4, 5, width - 6, width - 5])
      for (const y of [4, 5, height - 6, height - 5]) put(x, y, C.black);
  } else if (panel === 'glass') {
    fill(0, 0, width - 1, height - 1, [0, 0, 0, 0]);
  } else fill(0, 0, width - 1, height - 1, C.floor);
  draw({put, fill, line, rect, ellipse});
  const rows = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) pixels.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 6;
  fs.writeFileSync(path.join(root, name + '.png'), Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header),
    chunk('IDAT', zlib.deflateSync(rows, {level: 9})), chunk('IEND', Buffer.alloc(0)),
  ]));
  console.log(`${name}.png ${width}x${height}`);
}
image('pfd_frame', 420, 250, ({line, rect, ellipse}) => {
  // Fixed reticle and horizon; the moving diamond remains live telemetry.
  rect(84, 25, 336, 204); ellipse(210, 125, 113, 76, C.gridHi);
  for (const dy of [-56, -38, -19, 19, 38, 56]) {
    const width = Math.abs(dy) === 19 ? 34 : 19;
    line(210 - width, 125 + dy, 210 + width, 125 + dy, C.gridHi);
  }
  line(96, 125, 178, 125, C.green); line(242, 125, 324, 125, C.green);
  line(198, 125, 205, 132, C.green); line(205, 132, 210, 125, C.green);
  line(210, 125, 215, 132, C.green); line(215, 132, 222, 125, C.green);
  for (const x of [17, 341]) {
    rect(x, 47, x + 61, 189, C.gridHi);
    for (let y = 59; y < 185; y += 18) line(x + (y % 36 ? 6 : 2), y, x + 13, y);
  }
  line(91, 213, 329, 213, C.muted);
});
image('nav_frame', 420, 250, ({line, rect}) => {
  rect(31, 30, 388, 215, C.gridHi);
  for (let x = 91; x < 388; x += 60) line(x, 31, x, 214);
  for (let y = 67; y < 215; y += 37) line(32, y, 387, y);
  line(210, 30, 210, 215, C.gridHi); line(31, 125, 388, 125, C.gridHi);
  for (const x of [30, 210, 389]) { line(x, 20, x, 28, C.green); line(x, 216, x, 224, C.green); }
});
image('survey_frame', 420, 250, ({line, rect}) => {
  rect(34, 24, 385, 222, C.gridHi);
  for (let x = 69; x < 385; x += 35) line(x, 25, x, 221);
  for (let y = 49; y < 222; y += 25) line(35, y, 384, y);
  line(210, 25, 210, 221, C.green); line(35, 123, 384, 123, C.gridHi);
  line(204, 17, 210, 9, C.green); line(210, 9, 216, 17, C.green);
});
image('landing_frame', 420, 250, ({line, rect}) => {
  // Site-centred east/north plot. Its scale is chosen by live surface data.
  rect(34, 35, 385, 197, C.gridHi);
  for (let x = 69; x < 385; x += 35) line(x, 36, x, 196);
  for (let y = 55; y < 197; y += 20) line(35, y, 384, y);
  line(210, 36, 210, 196, C.green);
  line(35, 125, 384, 125, C.green);
  line(12, 207, 407, 207, C.gridHi);
});
image('mission_frame', 420, 180, ({line, rect}) => {
  line(12, 42, 407, 42, C.gridHi); rect(11, 46, 408, 110);
  line(12, 121, 407, 121, C.gridHi); line(12, 150, 407, 150);
});
image('systems_frame', 420, 180, ({line, rect}) => {
  line(12, 25, 407, 25, C.gridHi); rect(10, 29, 409, 96);
  line(12, 109, 407, 109, C.gridHi); line(12, 147, 407, 147);
});
image('twin_frame', 420, 250, ({line, rect}) => {
  line(12, 29, 407, 29, C.gridHi); rect(12, 37, 407, 232);
  for (let y = 68; y < 232; y += 31) line(13, y, 406, y);
  for (let x = 111; x < 407; x += 98) line(x, 38, x, 231);
});
image('vehicle_frame', 420, 250, ({line, rect}) => {
  rect(12, 30, 407, 231);
  for (let y = 62; y < 231; y += 32) line(13, y, 406, y);
});
image('descent_frame', 420, 120, ({line, rect}) => {
  rect(30, 15, 389, 105, C.gridHi); line(210, 16, 210, 104, C.gridHi);
  for (let y = 24; y < 105; y += 12) {
    line(30, y, 46, y, C.muted); line(374, y, 389, y, C.muted);
  }
  line(31, 105, 389, 105, C.green);
});
image('window_bg', 64, 64, ({line}) => {
  line(9, 10, 54, 10, C.gridHi);
});
image('readout_frame', 430, 480, ({line, rect}) => {
  // Permanent OPS-style telemetry bank; the labels and values are live widgets.
  rect(8, 8, 421, 471, C.gridHi);
  line(12, 39, 417, 39, C.green);
  for (let y = 77; y < 460; y += 28) line(16, y, 414, y, C.grid);
  line(17, 452, 37, 452, C.green);
  line(393, 452, 413, 452, C.green);
});
image('hud_clear', 64, 64, ({fill, line}) => {
  fill(0, 0, 63, 63, [3, 8, 9, 158]);
  line(0, 0, 63, 0, [26, 240, 52, 180]);
}, 'glass');
image('hud_overlay', 360, 240, ({line, rect}) => {
  // Transparent HUD geometry: kOS labels and the guidance bug remain live.
  for (const x of [18, 341]) {
    line(x, 22, x, 216, [26, 240, 52, 220]);
    for (let y = 22; y <= 216; y += 24) line(x, y, x + (x < 180 ? 9 : -9), y, [26, 240, 52, 180]);
  }
  rect(167, 107, 193, 133, [26, 240, 52, 210]);
  line(149, 120, 167, 120, [26, 240, 52, 210]);
  line(193, 120, 211, 120, [26, 240, 52, 210]);
  line(180, 90, 180, 107, [26, 240, 52, 210]);
  line(180, 133, 180, 150, [26, 240, 52, 210]);
  line(36, 202, 324, 202, [31, 102, 60, 165]);
}, 'glass');
function button(name, accent, base) {
  image(name, 96, 28, ({fill, line}) => {
    for (let y = 2; y < 26; y++) {
      const tint = Math.round((26 - y) * .37);
      fill(2, y, 93, y, rgb(base[0] + tint, base[1] + tint, base[2] + tint));
    }
    line(2, 2, 93, 2, accent); line(2, 25, 93, 25, C.black);
    line(1, 3, 1, 24, accent); line(94, 3, 94, 24, C.bezel);
  }, false);
}
button('button_off', C.gridHi, [38, 45, 50]);
button('button_hover', C.green, [50, 66, 68]);
button('button_on', C.green, [24, 74, 46]);
button('button_stby', C.bezel, [31, 37, 42]);
button('button_warn', C.amber, [79, 66, 28]);
button('button_fail', C.red, [103, 27, 29]);
