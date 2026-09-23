"""Offline UI2 regression gate: python tools/check-ui2.py (standard library only).

Checks PNG CRCs AND decompressed scanlines: permissive decoders can accept the
malformed files that caused Unity's red/white failed-texture backgrounds.
This is a static check, not an in-game KerboScript runtime test.
"""
from pathlib import Path
from collections import Counter
import re
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "AOSO/ux/ui2_assets"


def check_png(p):
    data = p.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{p.name}: signature"
    offset, compressed, tags = 8, bytearray(), []
    while offset < len(data):
        assert offset + 12 <= len(data), f"{p.name}: truncated chunk header"
        size, tag = struct.unpack_from(">I4s", data, offset)
        end = offset + 12 + size
        assert end <= len(data), f"{p.name}: truncated {tag!r}"
        payload = data[offset + 8:end - 4]
        crc, = struct.unpack_from(">I", data, end - 4)
        assert zlib.crc32(tag + payload) == crc, f"{p.name}: {tag!r} CRC"
        tags.append(tag)
        if tag == b"IHDR":
            width, height, bits, color, method, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            assert (bits, color, method, filtering, interlace) == (8, 6, 0, 0, 0), f"{p.name}: expected RGBA8"
        elif tag == b"IDAT":
            compressed.extend(payload)
        elif tag == b"IEND":
            assert size == 0 and end == len(data), f"{p.name}: trailing data"
        offset = end
    assert tags[0] == b"IHDR" and tags[-1] == b"IEND" and tags.count(b"IHDR") == tags.count(b"IEND") == 1
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(compressed) + decoder.flush()
    assert decoder.eof and not decoder.unused_data, f"{p.name}: incomplete/extra zlib stream"
    stride = width * 4 + 1
    assert len(pixels) == stride * height, f"{p.name}: incorrect scanline size"
    assert all(pixels[y * stride] <= 4 for y in range(height)), f"{p.name}: invalid PNG filter"
    if p.stem.endswith("_frame"):
        if p.stem == "readout_frame":
            assert (width, height) == (430, 480), f"{p.name}: changed readout dimensions"
        else:
            expected_height = {"descent_frame": 120, "mission_frame": 180, "systems_frame": 180}.get(p.stem, 250)
            assert (width, height) == (420, expected_height), f"{p.name}: changed widget dimensions"
    if p.stem == "hud_overlay":
        assert (width, height) == (360, 240), f"{p.name}: changed HUD dimensions"
    if p.stem in ("crt_go", "crt_asc", "crt_vs", "crt_rte", "crt_bdg", "crt_rnd", "crt_glass"):
        assert (width, height) == (740, 400), f"{p.name}: CRT plate must stay 740x400"


def code_only(source):
    # Preserve punctuation/newlines while excluding strings and comments.
    return re.sub(r'"(?:[^"\n]|"")*"|//[^\n]*', lambda m: " " * len(m[0]), source)


def main():
    pngs = [p for p in ASSETS.glob("*.png")]
    assert len(pngs) >= 27
    for p in pngs:
        check_png(p)
    for plate_name in ("crt_go.png", "crt_asc.png", "crt_vs.png", "crt_rte.png", "crt_bdg.png", "crt_rnd.png", "crt_glass.png"):
        # Size is asserted inside check_png via a side table below.
        assert (ASSETS / plate_name).is_file(), plate_name
    sources = {p: code_only(p.read_text(encoding="utf-8-sig")) for p in (ROOT / "AOSO").rglob("*.ks")}
    functions, globals_ = Counter(), set()
    for code in sources.values():
        functions.update(n.lower() for n in re.findall(r"\bFUNCTION\s+(\w+)", code, re.I))
        globals_.update(n.lower() for n in re.findall(r"\bGLOBAL\s+(\w+)\s+IS\b", code, re.I))
        assert not re.search(r"\bCLAMP\s*\(", code, re.I), "Unsupported built-in CLAMP call"
    ui_sources = {p: c for p, c in sources.items() if p.name.startswith("ui2_") or p.name == "hud_gui.ks"}
    for p, code in ui_sources.items():
        stack = []
        for ch in code:
            if ch in "([{":
                stack.append(ch)
            elif ch in ")]}":
                assert stack and stack.pop() == {")": "(", "]": "[", "}": "{"}[ch], f"{p.name}: delimiters"
        assert not stack, f"{p.name}: unclosed delimiters"
        for name in re.findall(r"\bFUNCTION\s+(\w+)", code, re.I):
            assert functions[name.lower()] == 1 and name.lower() not in globals_, f"{p.name}: collision {name}"
        assert not re.search(r"\b(?:LOCAL|PARAMETER)\s+(?:path|obt|note|alt|r|v|q|status|heading)\b", code, re.I), f"{p.name}: reserved name"
        assert not re.search(r"\bIF\s+NOT\s+DEFINED\b", code, re.I), f"{p.name}: IF NOT DEFINED"
        assert not re.search(r"\b(?:UNLOCK|LOCK)\s+(?:STEERING|THROTTLE)|\bSET\s+(?:WARP|WARPMODE|THROTTLE|SHIP\s*:\s*CONTROL)\b|\bSTAGE\s*\(", code, re.I), f"{p.name}: flight-control write"
        for call in re.findall(r"\b(aoso_\w+)\s*\(", code, re.I):
            assert functions[call.lower()] == 1, f"{p.name}: undefined/duplicate helper {call}"
    boot = (ROOT / "AOSO/main.ks").read_text()
    assert boot.index('"AOSO/ux/ui2_instruments"') < boot.index('"AOSO/ux/ui2_hud"') < boot.index('"AOSO/ux/ui2_mfd"')
    assert boot.index('"AOSO/ux/ui2_plots"') < boot.index('"AOSO/ux/ui2_go"') < boot.index('"AOSO/ux/hud_gui"')
    assert boot.index('"AOSO/mission/launch_hold"') < boot.index('"AOSO/ux/ui2_go"')
    gui_code = sources[ROOT / "AOSO/ux/hud_gui.ks"]
    assert len(re.findall(r"\baoso_ops_readout\s*\(", gui_code, re.I)) >= 6
    assert "crt_asc.png" in (ROOT / "AOSO/ux/hud_gui.ks").read_text()
    gui_source = (ROOT / "AOSO/ux/hud_gui.ks").read_text()
    for asset in re.findall(r'"([a-z_]+\.png)"', gui_source[gui_source.index("LOCAL image_files IS LIST("):gui_source.index("FOR image_file IN image_files")]):
        assert (ASSETS / asset).is_file(), f"missing startup art {asset}"
    assert 'AOSO_UI2_SURF_MAIN:STYLE:BG TO AOSO_UI2_ASSET_ROOT + "landing_frame.png"' in (ROOT / "AOSO/ux/ui2_instruments.ks").read_text()
    print(f"PASS: {len(pngs)} PNG streams; {len(ui_sources)} UI2 modules; all AOSO scripts free of bare CLAMP calls; helper load order")


if __name__ == "__main__":
    main()
