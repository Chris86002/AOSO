"""Explain an AOSO HUD dump: python tools/inspect-hud-dump.py aoso_hud.json.

In-game: open the separate HUD, press DUMP, then copy
<KSP>/Ships/Script/aoso_hud.json to this command. TEST cycles known geometry.
This tool never changes a save or sends commands to KSP.
"""
import argparse
import json
from pathlib import Path


def inspect(data):
    issues = []
    lines = []
    ready = data.get("ops_ui_ready")
    lines.append(f"OPS UI: {'READY' if ready else 'FAULT'} ({data.get('ops_ui_reason', 'reason missing')})")
    if not ready:
        issues.append("Startup self-test failed; inspect missing artwork or widgets.")
    visible = data.get("hud_visible")
    mode = int(data.get("hud_test", 0))
    lines.append(f"HUD: {'visible' if visible else 'hidden'}; geometry mode {mode} (0=live, 1=center, 2=edge)")
    x, y = data.get("hud_bug_x"), data.get("hud_bug_y")
    lines.append(f"Guidance bug: ({x}, {y}) on 360 x 240 glass")
    if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
        issues.append("Guidance bug coordinates are missing from the dump.")
    elif not (0 <= x <= 360 and 0 <= y <= 240):
        issues.append("Guidance bug is outside its HUD glass; check projection/margins.")
    age = data.get("hi_age")
    lines.append(f"Flight telemetry age: {age}s; page={data.get('page')} ctx={data.get('ctx')}")
    if not isinstance(age, (int, float)) or age > 2:
        issues.append("Flight telemetry is stale; inspect the HUD scheduler and CPU load.")
    lines.append(f"CPU: {data.get('cpu')}  IPU: {data.get('ipu')}  last event: {data.get('last_evt')}")
    if data.get("last_err"):
        lines.append(f"Last error: {data['last_err']}")
    return lines, issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dump", type=Path, help="aoso_hud.json from the kOS archive")
    args = parser.parse_args()
    data = json.loads(args.dump.read_text(encoding="utf-8-sig"))
    lines, issues = inspect(data)
    print("\n".join(lines))
    print("\nDiagnosis:")
    print("\n".join("- " + issue for issue in issues) if issues else "- No layout or freshness fault visible in this dump.")


if __name__ == "__main__":
    main()
