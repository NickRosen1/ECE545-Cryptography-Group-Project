#!/usr/bin/env python3
"""
gen_vectors.py - Generate extra ISAP-A-128A (AEAD-only) LWC test vectors with
the ISAP team's own generator script, software/cryptotvgen/examples/genkat_v1.py.

The official v1 KAT only covers AD and message lengths of 0..32 bytes. This
runs the same generator (same cryptotvgen settings, same decryption reordering
post-processing, same ISAP reference C library) with a different list of
cases: many-block messages up to 1,500 bytes, every block-boundary length,
key reuse, and no hash messages. Expected outputs come from the reference C
code; each is cross-checked by running it on the original VHDL design.

Requires: pip install software/cryptotvgen   (plus setuptools<70, requests)

Usage: python3 gen_vectors.py <dest dir> [seed]
"""
import os
import random
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
GENKAT = REPO / "software" / "cryptotvgen" / "examples" / "genkat_v1.py"


def cases(seed):
    rnd = random.Random(seed)
    edge = [0, 1, 3, 4, 5, 7, 8, 9, 12, 15, 16, 17, 23, 24, 25, 31, 32, 33, 40, 47, 48, 49, 63, 64, 65]
    out = []
    # every pairing of block-boundary lengths, encrypt and decrypt
    for ad in edge[::2]:
        for pt in edge[1::2]:
            out.append((rnd.random() < 0.5, rnd.random() < 0.5, ad, pt))
    # random lengths up to 200 bytes
    for _ in range(120):
        out.append((rnd.random() < 0.5, rnd.random() < 0.5, rnd.randint(0, 200), rnd.randint(0, 200)))
    # long messages (many blocks), both directions
    for ad, pt in [(0, 1024), (1024, 0), (513, 511), (1500, 1500), (7, 1001), (999, 9)]:
        out.append((True, False, ad, pt))
        out.append((True, True, ad, pt))
    rnd.shuffle(out)
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    dest = Path(sys.argv[1]).resolve()
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 545
    src = GENKAT.read_text()
    a = src.index("'''\\")
    b = src.index("'''", a + 4)
    custom = "".join(f"{nk},\t{dec},\t{ad},\t{pt},\tFalse:\n" for nk, dec, ad, pt in cases(seed))
    custom = custom.rstrip(":\n") + "\n"
    src = src[:a] + "'''\\\n" + custom + src[b:]
    src = src.replace("dest_dir = f'testvectors/v1_{ccw}'", f"dest_dir = r'{dest}'")
    src = src.replace("'--max_ad', '80'", "'--max_ad', '1500'").replace("'--max_d', '80'", "'--max_d', '1500'")
    # cryptotvgen's --verify_lib path crashes with nsec_size=0 on this version
    # (AttributeError nsec_pt). Each vector is instead cross-checked by running
    # it through the original VHDL design, which must pass (run_golden.sh).
    src = src.replace("'--verify_lib',", "")
    assert f"r'{dest}'" in src, "genkat_v1.py changed; update gen_vectors.py"
    os.makedirs(dest, exist_ok=True)
    glb = {"__name__": "__main__", "__file__": str(GENKAT)}
    exec(compile(src, str(GENKAT), "exec"), glb)
    print(f"wrote {len(cases(seed))} AEAD test vectors to {dest}")


if __name__ == "__main__":
    main()
