#!/usr/bin/env python3
"""Run selected pure KerboScript helpers against flight regressions.

This is a limited helper evaluator, not a kOS compiler or KSP simulation.
It reads the production functions; unsupported statements fail explicitly.
Run from any directory: python tools/check-landing-regressions.py
"""
import math
import re
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]


class Lex(dict):
    def haskey(self, key):
        return key in self


class Vec:
    def __init__(self, x, y):
        self.x, self.y = x, y

    @property
    def mag(self):
        return math.hypot(self.x, self.y)

    @property
    def normalized(self):
        return self * (1 / self.mag)

    def __mul__(self, scale):
        return Vec(self.x * scale, self.y * scale)

    def __add__(self, other):
        return Vec(self.x + other.x, self.y + other.y)

    def __sub__(self, other):
        return Vec(self.x - other.x, self.y - other.y)


def lexicon(*items):
    return Lex(zip(items[::2], items[1::2]))


CONFIG = {}
ENV = {
    "sqrt": math.sqrt, "max": max, "min": min, "abs": abs,
    "sin": lambda x: math.sin(math.radians(x)),
    "tan": lambda x: math.tan(math.radians(x)),
    "arccos": lambda x: math.degrees(math.acos(x)),
    "lexicon": lexicon,
    "aoso_const": {"DEG2RAD": math.pi / 180},
    "constant_pi": math.pi,
    "aoso_config_get": lambda key, default: CONFIG.get(key, default),
    "time_seconds": 1000,
}


def production_body(relpath, name):
    text = (ROOT / relpath).read_text()
    start = re.search(r"FUNCTION\s+" + re.escape(name) + r"\s*\{", text, re.I).end()
    depth, index = 1, start
    while depth:
        depth += (text[index] == "{") - (text[index] == "}")
        index += 1
    return text[start:index - 1]


def expression(text):
    # Preserve string literals while translating kOS's scalar operators.
    out = []
    for part in re.split(r'("[^"\n]*")', text):
        if part.startswith('"'):
            out.append(part)
            continue
        part = part.lower().replace("constant:pi", "constant_pi")
        part = part.replace("time:seconds", "time_seconds")
        part = part.replace(":haskey", ".haskey")
        part = re.sub(r":([a-z_]\w*)", r".\1", part)
        part = part.replace("<>", "!=").replace("^", "**")
        part = re.sub(r"(?<![<>=!])=(?!=)", "==", part)
        part = re.sub(r"\btrue\b", "True", part)
        part = re.sub(r"\bfalse\b", "False", part)
        out.append(part)
    return "".join(out).strip()


def load_helper(relpath, name):
    body = re.sub(r"//[^\n]*", "", production_body(relpath, name))
    # These helpers contain scalar statements and no strings with punctuation.
    tokens = re.split(r"([{}]|\.(?!\d))", body)
    params, statements, indent = [], [], 1
    for token in tokens:
        token = " ".join(token.split())
        if not token or token == ".":
            continue
        if token == "{":
            indent += 1
            continue
        if token == "}":
            indent -= 1
            continue
        parameter = re.fullmatch(r"PARAMETER (\w+)(?: IS (.*))?", token, re.I)
        local = re.fullmatch(r"LOCAL (\w+) IS (.*)", token, re.I)
        assign = re.fullmatch(r"SET (.*?) TO (.*)", token, re.I)
        if parameter:
            arg = parameter[1].lower()
            if parameter[2]:
                arg += "=" + expression(parameter[2])
            params.append(arg)
            continue
        if local:
            line = local[1].lower() + " = " + expression(local[2])
        elif assign:
            line = expression(assign[1]) + " = " + expression(assign[2])
        elif token.upper().startswith("IF "):
            line = "if " + expression(token[3:]) + ":"
        elif token.upper().startswith("ELSE IF "):
            line = "elif " + expression(token[8:]) + ":"
        elif token.upper() == "ELSE":
            line = "else:"
        elif token.upper().startswith("RETURN "):
            line = "return " + expression(token[7:])
        else:
            raise AssertionError(f"Unsupported helper statement: {token}")
        statements.append("    " * indent + line)
    source = f"def {name}({', '.join(params)}):\n" + "\n".join(statements)
    exec(compile(source, f"{relpath}:{name}", "exec"), ENV)
    return ENV[name]


ready = load_helper("AOSO/landing/descent.ks", "aoso_descent_terminal_ready")
arc = load_helper("AOSO/mission/tour.ks", "aoso_tour_deorbit_arc")
exhausted = load_helper("AOSO/mission/tour.ks", "aoso_tour_landing_budget_exhausted")

# Recorded states: initial braking must remain full-thrust; the safe arrest
# at 564 m must hand off BEFORE the subsequent ascent/downward-thrust cycle.
assert not ready(-19.5, 182, 480 / 47.6, 0.462)
assert ready(-3, 13.2, 10.5, 0.462)
assert ready(1.2, 8.1, 10.5, 0.462)
assert ready(15.2, 16.4, 10.5, 0.462)
assert not ready(-40, 0, 1.0, 0.462)
assert ready(-3, 0, 10.5, 0.462)
print("PASS: logged arrest hands off; initial/low-TWR braking remains active")

# Evaluate the actual terminal guidance function in a small constant-gravity
# local model. This checks the early-arrest recovery and upright thrust sign;
# it does not model attitude slew, terrain, engine spool, or KSP physics.
guide = load_helper("AOSO/landing/descent.ks", "aoso_descent_terminal_guidance")
up = Vec(0, 1)
ENV.update({
    "vxcl": lambda axis, velocity: Vec(velocity.x, 0),
    "aoso_descent_true_radar": lambda: ENV["clearance"],
    "aoso_descent_local_gravity": lambda: 0.462,
})
height, vs, hs, elapsed, fuel_equiv = 564.0, -3.0, 13.2, 0.0, 0.0
while height > 0.5 and elapsed < 180:
    ENV.update(clearance=height, verticalspeed=vs)
    ENV["ship"] = SimpleNamespace(mass=47.6, availablethrust=480,
                                  up=SimpleNamespace(vector=up),
                                  velocity=SimpleNamespace(surface=Vec(hs, vs)))
    cmd = guide(Lex())
    assert cmd["direction"].y >= 0
    assert 0 <= cmd["throttle"] <= 1
    thrust = cmd["direction"].normalized * (cmd["throttle"] * 480 / 47.6)
    dt = 0.02
    vs += (thrust.y - 0.462) * dt
    hs += thrust.x * dt
    height += vs * dt
    fuel_equiv += thrust.mag * dt
    elapsed += dt
assert height <= 0.5 and -3 < vs < 0 and abs(hs) < 1.5, (height, vs, hs)
assert fuel_equiv < 100
print(f"PASS: early-arrest recovery reaches ground in {elapsed:.1f} s at "
      f"VS {vs:.2f}, HS {hs:.2f} m/s, ideal thrust dV {fuel_equiv:.1f} m/s")

# Independently verify the first surface crossing against conic radius and
# Kepler time; targeting the old 180-degree antipode is observably too late.
mu, apo, pe, surface = 1.7658e9, 89260, 59500, 60000
crossing = arc(apo, pe, surface, mu)
assert crossing["ok"]
sma, ecc = (apo + pe) / 2, (apo - pe) / (apo + pe)
nu = math.radians(180 + crossing["angle"])
radius = sma * (1 - ecc**2) / (1 + ecc * math.cos(nu))
assert abs(radius - surface) < 1e-6
half_period = math.pi * math.sqrt(sma**3 / mu)
assert 0 < crossing["coast"] < half_period
assert 0 < crossing["angle"] < 180
assert not arc(apo, 61000, surface, mu)["ok"]
print(f"PASS: surface crossing at {crossing['angle']:.2f} degrees / "
      f"{crossing['coast']:.1f} s; periapsis would be {half_period:.1f} s")

assert not exhausted(Lex(landing_retries=0, landing_deadline_ut=2000))
assert not exhausted(Lex(landing_retries=2, landing_deadline_ut=2000))
assert exhausted(Lex(landing_retries=3, landing_deadline_ut=2000))
assert exhausted(Lex(landing_retries=0, landing_deadline_ut=1000))
print("PASS: attempt and shared time limits stop repeated planning")

# Within the current SOI, kOS propagates the vessel about the body's CURRENT
# centre. Simulate a moon travelling 200 km around its parent: that movement
# must not appear in the vessel's landing radius or latitude/longitude.
position_at = load_helper("AOSO/landing/impact.ks", "aoso_landing_position_at")
body_now = SimpleNamespace(name="Minmus", position=Vec(-80000, 3000))
ENV.update({
    "ship": SimpleNamespace(body=body_now),
    "orbitat": lambda vessel, epoch: SimpleNamespace(body=body_now),
    "positionat": lambda vessel, epoch: body_now.position + Vec(60000, 0),
    "v": lambda x, y, z: Vec(x, y),
})
assert abs(position_at(2000).mag - 60000) < 1e-6
ENV["orbitat"] = lambda vessel, epoch: SimpleNamespace(body=SimpleNamespace(name="Kerbin"))
assert position_at(2000).mag == 0
print("PASS: landing uses the fixed current SOI centre and refuses another SOI")

# Ensure the source-level coordination paths remain connected.
burn = production_body("AOSO/landing/descent.ks", "aoso_descent_burn_execute")
assert burn.index("aoso_descent_should_terminal()") < burn.index("aoso_descent_suicide_command(data)")
assert "SHIP:SRFRETROGRADE:VECTOR" not in production_body(
    "AOSO/landing/descent.ks", "aoso_descent_suicide_command")
assert "WAIT" not in production_body("AOSO/vehicle/staging.ks", "aoso_staging_emit")
xp_save = production_body("AOSO/vehicle/experience.ks", "aoso_xp_save")
assert xp_save.index("aoso_xp_persist_allowed()") < xp_save.index("aoso_json_write_persistent(")
impact = production_body("AOSO/landing/impact.ks", "aoso_landing_position_at")
assert "POSITIONAT(SHIP, sample_ut) - SHIP:BODY:POSITION" in impact
assert "POSITIONAT(SHIP:BODY" not in impact
print("PASS: control handoff, frame correction, and persistence gates connected")

print("Landing regression checks passed (helper evaluation; no in-game validation).")
