#!/usr/bin/env python3
"""pick-path: the route is in walking order, the saving is computed not stored, and a short bin is recorded short."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "pick_server")
CAP = os.path.join(HERE, "captures")
SERVER_ID = "com.makemind.sample.pick"

with Server(["dart", "run", "bin/server.dart"], cwd=SERVER) as s:
    start = s.call("pick.state")
    slots = [r["slot"] for r in start["rows"]]
    assert slots == sorted(slots), "the route must be in walking order"
    src = open(os.path.join(SERVER, "bin", "server.dart")).read()
    assert str(start["saved"]).split()[0] not in src, "the saving must be computed, never stored"

ap = AppPlayer()
ap.register_server(SERVER_ID, "Pick list", cwd=SERVER)
ap.restart()
ap.open_server(SERVER_ID)
ap.wait_text("go here")
ap.shot(f"{CAP}/01_route.png")
for label, done in (("Took 6", "1 / 5"), ("Took 2", "2 / 5"), ("Took 2", "3 / 5")):
    ap.tap(label)
    ap.wait_text(done)
ap.wait_text("short")
ap.shot(f"{CAP}/02_short.png")
ap.tap("Took 1")
ap.wait_text("4 / 5")
ap.tap("Took 3")
ap.wait_text("5 / 5")
ap.expect_text("SKU-1183 short 2")
ap.shot(f"{CAP}/03_done.png")
print("pick-path: walking order, computed saving, the cable tidy recorded short")
