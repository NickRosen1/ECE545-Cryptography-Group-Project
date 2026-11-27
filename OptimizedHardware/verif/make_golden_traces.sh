#!/usr/bin/env bash
# make_golden_traces.sh - Regenerate every golden trace from the ORIGINAL VHDL
# design (needs GHDL). Run once; the traces only change if the vectors change.
#
#   official_*  : the ISAP team's v1 KAT, AEAD records only (648 messages)
#   extended_*  : 288 extra AEAD vectors from gen_vectors.py (up to 1,500 bytes)
#   badtag_*    : forged tags (see vectors/corrupt_tags.py)
# mode0 = no stalls, mode1 = stalls on inputs and outputs.
set -euo pipefail
cd "$(dirname "$0")"
V=vectors
mkdir -p traces
rm -f traces/*.trc traces/*.log traces/*.txt

[ -d $V/kat_v1_official_aead ] || python3 -I $V/filter_aead.py ../../hardware/isap_lwc/KAT/v1 $V/kat_v1_official_aead
[ -d $V/kat_extended ] || { echo "run vectors/gen_vectors.py vectors/kat_extended first"; exit 1; }
for k in 0 1 3 6 10; do
    [ -d $V/kat_badtag_ext_$k ] || python3 -I $V/corrupt_tags.py $V/kat_extended $V/kat_badtag_ext_$k $k
done
[ -d $V/kat_badtag_official_0 ] || python3 -I $V/corrupt_tags.py $V/kat_v1_official_aead $V/kat_badtag_official_0 0

for m in 0 1; do
    golden/run_golden.sh $V/kat_v1_official_aead $m traces/official_mode$m.trc
    golden/run_golden.sh $V/kat_extended         $m traces/extended_mode$m.trc
    golden/run_golden.sh $V/kat_badtag_official_0 $m traces/badtag_official_mode$m.trc 100000
done
for k in 0 1 3 6 10; do
    golden/run_golden.sh $V/kat_badtag_ext_$k 0 traces/badtag_ext${k}_mode0.trc 100000
done
echo
echo "Golden traces written to $(pwd)/traces."
echo "official_* and extended_* must say [PASS]; badtag_* fail on purpose (forged tags)."
grep -l "\[PASS\]" traces/official_mode*.log traces/extended_mode*.log
