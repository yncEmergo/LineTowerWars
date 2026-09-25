# Tabulates LockstepProbe runs: one block per scenario, the PROBE RESULT fields of each
# client and a count of the relay lines that matter. Reads the summary.txt files that
# run_lockstep_probe.ps1 writes.
#
#   python Tools/probe_table.py %TEMP%\ltw_probe\runs

import os
import re
import sys

ROOT = sys.argv[1]
FIELDS = ["turns_run", "orders_applied", "stalls", "stalled_s", "desyncs", "drops_seen",
          "pause_turn", "resume_turn", "gave_up", "sealed_held", "echo", "repair", "units",
          "hitches", "spoofs_sent"]
RELAY_KEYS = ["Initial world agrees", "Initial world DIFFERS", "Sealed stream opened",
              "gone silent", "Player dropped", "diverged", "disagree", "SCRIPT ERROR", "ERROR:"]


def field(line, name):
    m = re.search(r'"%s": (\[[^\]]*\]|[^,}]+)' % name, line)
    return m.group(1).strip() if m else "?"


for scenario in sorted(os.listdir(ROOT)):
    path = os.path.join(ROOT, scenario, "summary.txt")
    if not os.path.exists(path):
        continue
    with open(path, encoding="utf-8-sig") as f:
        lines = [l.rstrip("\n") for l in f]
    print("=== %s   %s" % (scenario, lines[0].split("  ", 1)[1] if lines else ""))
    for line in lines:
        if "HARD-KILLED" in line:
            print("   " + line)
        m = re.match(r"\[(\w+)\].*PROBE RESULT", line)
        if m:
            vals = ", ".join("%s=%s" % (n, field(line, n)) for n in FIELDS)
            print("   %-6s %s" % (m.group(1), vals))
        elif re.match(r"\[(\w+)\] NO PROBE RESULT", line):
            print("   " + line)
    relay = [l for l in lines if l.startswith("[relay]")]
    counts = []
    for key in RELAY_KEYS:
        n = sum(1 for l in relay if key in l)
        if n:
            counts.append("%s x%d" % (key, n))
    print("   relay: " + "; ".join(counts))
