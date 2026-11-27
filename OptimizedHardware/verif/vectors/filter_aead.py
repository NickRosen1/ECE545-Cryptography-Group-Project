#!/usr/bin/env python3
"""
filter_aead.py - Copy an LWC KAT set (pdi.txt, sdi.txt, do.txt), dropping the
standalone Ascon-Hash messages so only ISAP-A-128A AEAD messages remain.

Records are kept byte-for-byte and in their original order. The SDI file holds
only keys, which only AEAD messages use, so it is copied unchanged.

Usage: python3 filter_aead.py <src KAT dir> <dest dir>
"""
import os
import shutil
import sys


def filter_file(src, dst):
    lines = open(src).read().split("\n")
    out, i, kept, dropped = [], 0, 0, 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("#### Hash") or line.startswith("#### Authenticated"):
            # a record runs from its section header to the next header or EOF marker
            j = i + 1
            while j < len(lines) and not (
                lines[j].startswith("#### Hash")
                or lines[j].startswith("#### Authenticated")
                or lines[j].startswith("###EOF")
            ):
                j += 1
            if line.startswith("#### Hash"):
                dropped += 1
            else:
                out.extend(lines[i:j])
                kept += 1
            i = j
        else:
            out.append(line)
            i += 1
    with open(dst, "w") as f:
        f.write("\n".join(out))
    return kept, dropped


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for name in ("pdi.txt", "do.txt"):
        kept, dropped = filter_file(os.path.join(src, name), os.path.join(dst, name))
        print(f"{name}: kept {kept} AEAD records, dropped {dropped} hash records")
    shutil.copy(os.path.join(src, "sdi.txt"), os.path.join(dst, "sdi.txt"))


if __name__ == "__main__":
    main()
