#!/usr/bin/env python3
"""
Compare a PK PDF import JSON result against the original .stitches file.

Usage: compare_round_trip.py <import_json_path> <stitches_path>
"""
import sys
import json
import yaml

def main():
    import_json_path = sys.argv[1]
    stitches_path    = sys.argv[2]

    with open(import_json_path) as f:
        import_json = json.load(f)

    with open(stitches_path, 'rb') as f:
        raw = f.read()
    # .stitches files may be gzip-compressed
    if raw[:2] == b'\x1f\x8b':
        import gzip
        raw = gzip.decompress(raw)
    # pyyaml rejects control characters (e.g. symbol glyphs like 0x05 used for
    # DMC thread symbols). Replace them with '?' — we don't use symbol values.
    sanitised = bytes(
        b if (b >= 0x20 or b in (0x09, 0x0a, 0x0d)) else ord('?')
        for b in raw
    )
    doc = yaml.safe_load(sanitised.decode('utf-8'))

    pattern = doc['pattern']
    src_w = pattern['width']
    src_h = pattern['height']

    # Collect all full stitches from layerItems (v2 format).
    # Each stitch has: type, x, y, thread (= DMC code directly).
    src_stitches = set()
    src_threads  = set()

    def collect_layer_items(items):
        for item in (items or []):
            item_type = item.get('type')
            if item_type == 'layer':
                for s in item.get('stitches', []):
                    stype = s.get('type', 'full')
                    dmc   = s.get('thread') or s.get('threadId', '?')
                    src_threads.add(dmc)
                    if stype == 'full':
                        src_stitches.add((s['x'], s['y'], dmc))
            elif item_type == 'group':
                collect_layer_items(item.get('layerItems', []))

    collect_layer_items(pattern.get('layerItems', []))

    # Build import stitch set
    imp_stitches = set()
    for s in import_json.get('stitches', []):
        if s['type'] == 'full':
            imp_stitches.add((s['x'], s['y'], s['dmcCode']))

    # Thread comparison (order-independent, guid-free)
    imp_threads = set(t['dmcCode'] for t in import_json.get('threads', []))

    print(f"  Source:  {src_w}×{src_h}, {len(src_threads)} threads, {len(src_stitches)} full stitches")
    print(f"  Import:  {import_json['width']}×{import_json['height']}, {len(imp_threads)} threads, {len(imp_stitches)} full stitches")

    # Stitch diff
    missing = src_stitches - imp_stitches
    extra   = imp_stitches - src_stitches

    ok = True
    if not missing and not extra:
        print(f"  ✅ PERFECT MATCH — all {len(src_stitches)} stitches match")
    else:
        ok = False
        if missing:
            sample = sorted(missing)[:10]
            print(f"  ❌ MISSING {len(missing)} stitches (first 10: {sample})")
        if extra:
            sample = sorted(extra)[:10]
            print(f"  ❌ EXTRA   {len(extra)} stitches (first 10: {sample})")

    t_missing = src_threads - imp_threads
    t_extra   = imp_threads - src_threads
    if t_missing:
        ok = False
        print(f"  ❌ Threads missing from import: {sorted(t_missing)}")
    if t_extra:
        print(f"  ⚠️  Extra threads in import (blends/alias?): {sorted(t_extra)}")

    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
