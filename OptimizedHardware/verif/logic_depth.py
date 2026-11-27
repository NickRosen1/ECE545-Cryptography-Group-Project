#!/usr/bin/env python3
"""
logic_depth.py - Rough timing proxy from a Yosys 7-series netlist (JSON).

Counts the deepest chain of logic cells (LUTs, MUXF7/8, CARRY4) between
registers or ports, and lists how many register-to-register paths reach each
depth. Real timing (Fmax, WNS) only comes from Vivado; this just shows
whether a change made the critical path deeper.

Usage: python3 logic_depth.py <netlist.json>
"""
import json
import sys
from collections import defaultdict
from functools import lru_cache

sys.setrecursionlimit(100000)
LOGIC = ("LUT", "MUXF", "CARRY", "INV")


def main():
    net = json.load(open(sys.argv[1]))
    (mod,) = [m for m in net["modules"].values() if m.get("attributes", {}).get("top")] or \
        [list(net["modules"].values())[0]]
    drivers = {}       # bit -> cell name
    cell_in = {}       # cell -> list of input bits
    kind = {}
    for name, c in mod["cells"].items():
        t = c["type"]
        kind[name] = t
        ins = []
        for port, bits in c["connections"].items():
            d = c.get("port_directions", {}).get(port, "input")
            for b in bits:
                if isinstance(b, str):
                    continue
                if d == "output":
                    drivers[b] = name
                else:
                    ins.append(b)
        cell_in[name] = ins

    NEG = -10**9

    @lru_cache(maxsize=None)
    def depth(cell, from_ports):
        # from_ports: True  -> paths starting at module inputs only
        #             False -> paths starting at registers only
        if not kind[cell].startswith(LOGIC):
            return NEG if from_ports else 0      # a register starts a path
        best = NEG
        for b in cell_in[cell]:
            src = drivers.get(b)
            if src is None:                       # module input port
                if from_ports:
                    best = max(best, 0)
            elif kind[src].startswith(LOGIC):
                best = max(best, depth(src, from_ports))
            elif not from_ports:
                best = max(best, 0)
        return best + 1 if best > NEG else NEG

    for label, fp in (("register -> register", False), ("input port -> register", True)):
        hist = defaultdict(int)
        worst = 0
        for name, t in kind.items():
            if t.startswith("FD"):
                for b in cell_in[name]:
                    src = drivers.get(b)
                    if src is None:
                        continue
                    d = depth(src, fp) if kind[src].startswith(LOGIC) else (NEG if fp else 0)
                    if d < 0:
                        continue
                    hist[d] += 1
                    worst = max(worst, d)
        print(f"{label:24s}: max {worst} logic levels; endpoints at the top depths: "
              + ", ".join(f"{k} levels x{hist[k]}" for k in sorted(hist) if k >= worst - 2))


if __name__ == "__main__":
    main()
