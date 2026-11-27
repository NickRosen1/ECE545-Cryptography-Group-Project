#!/usr/bin/env python3
"""
corrupt_tags.py - Build a "bad tag" stimulus set from an AEAD KAT set.

Every decryption with an empty ciphertext gets one tag bit flipped (the
upstream LWC wrapper completes these with a failure status). The set is then
cut off after the first decryption with a NON-empty ciphertext, whose tag is
also corrupted: the upstream wrapper never finishes such a message (a known,
inherited PostProcessor limitation), so nothing after it could run anyway.

The expected outputs in do.txt are NOT updated, so the LWC testbench reports
these messages as failures. That is intended: this set is only used to record
how the ORIGINAL core rejects forged tags (msg_auth = 0, no plaintext released),
and the trace of that behaviour is what the optimized core must reproduce.

Usage: python3 corrupt_tags.py <src KAT dir> <dest dir> [stop_at]
  stop_at = k  : stop at the k-th decryption with a NON-empty ciphertext
                 (k = 1 by default); earlier ones are left valid, so the
                 run reaches deeper into the set before the wrapper stalls.
  stop_at = 0  : corrupt only empty-ciphertext decryptions and keep the
                 whole set (the wrapper completes all of these).
"""
import os
import re
import shutil
import sys


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    stop_at = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    n_nonempty = 0
    os.makedirs(dst, exist_ok=True)
    lines = open(os.path.join(src, "pdi.txt")).read().split("\n")
    out, rec_dec, rec_ct, n_bad, n_rec = [], False, 0, 0, 0
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("#### Authenticated") or line.startswith("###EOF"):
            rec_dec = "Decryption" in line
            n_rec += 1
        m = re.search(r"CT Size=(\d+)", line)
        if m:
            rec_ct = int(m.group(1))
        if rec_dec and line.startswith("HDR = 83") and i + 1 < len(lines) and lines[i + 1].startswith("DAT = "):
            if rec_ct > 0:
                n_nonempty += 1
                if stop_at == 0 or n_nonempty < stop_at:   # leave this one valid
                    out.append(line)
                    i += 1
                    continue
            out.append(line)
            tag = int(lines[i + 1][6:], 16)
            bit = [127, 64, 0, 31, 96][n_bad % 5]
            out.append("DAT = {:032X}".format(tag ^ (1 << bit)))
            n_bad += 1
            i += 2
            if rec_ct > 0:
                # keep the rest of this record, then stop
                while i < len(lines) and not lines[i].startswith("####"):
                    out.append(lines[i])
                    i += 1
                rec_dec, rec_ct = True, 1
                break
            continue
        out.append(line)
        i += 1
    while out and out[-1].strip() == "":
        out.pop()
    if out[-1] != "###EOF":
        out.append("###EOF")
    open(os.path.join(dst, "pdi.txt"), "w").write("\n".join(out) + "\n")
    shutil.copy(os.path.join(src, "sdi.txt"), os.path.join(dst, "sdi.txt"))
    shutil.copy(os.path.join(src, "do.txt"), os.path.join(dst, "do.txt"))
    print(f"{n_bad} corrupted tags in the first {n_rec} records -> {dst}")


if __name__ == "__main__":
    main()
