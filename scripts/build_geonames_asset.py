#!/usr/bin/env python3
"""Build a compact binary cities500 asset for on-device reverse geocoding.

Input: cities500.txt (GeoNames, tab-separated)
Output: assets/geocoder/cities500.bin

Binary layout (little-endian):
  Header (16 bytes):
    magic   : 4 bytes = b'GCT2'
    count   : uint32  (number of records)
    str_off : uint32  (byte offset of string table)
    reserved: uint32
  Records (count * 14 bytes each, sorted by latitude):
    lat_e5  : int32   (lat * 1e5)
    lng_e5  : int32   (lng * 1e5)
    name_off: uint32  (offset within string table)
    pop_log : uint16  (log10(pop+1) * 1000, clamped to uint16)
  String table (variable):
    For each entry: 1 byte name_len, name (utf8), 2 bytes country (ascii),
                    1 byte admin1_len, admin1 (ascii)
"""
import gzip
import struct
import sys
import os

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/cities500.txt"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(__file__), "..", "assets", "geocoder", "cities500.bin.gz"
)

rows = []
with open(SRC, "r", encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 15:
            continue
        ascii_name = parts[2] or parts[1]
        try:
            lat = float(parts[4])
            lng = float(parts[5])
        except ValueError:
            continue
        cc = parts[8] or ""
        admin1 = parts[10] or ""
        try:
            pop = int(parts[14]) if parts[14] else 0
        except ValueError:
            pop = 0
        rows.append((lat, lng, ascii_name, cc, admin1, pop))

print(f"Loaded {len(rows)} rows")

# Dedup by (rounded lat,lng,name) and prefer higher population.
rows.sort(key=lambda r: (-r[5], r[2]))
seen = set()
deduped = []
for r in rows:
    key = (round(r[0], 3), round(r[1], 3), r[2].lower())
    if key in seen:
        continue
    seen.add(key)
    deduped.append(r)
print(f"Deduped to {len(deduped)} rows")

# Sort by lat ascending for prefilter optimization.
deduped.sort(key=lambda r: r[0])

# Build string table.
strtab = bytearray()
name_offsets = []
str_index = {}
for lat, lng, name, cc, admin1, pop in deduped:
    key = (name, cc, admin1)
    if key in str_index:
        name_offsets.append(str_index[key])
        continue
    nb = name.encode("utf-8")
    if len(nb) > 255:
        nb = nb[:255]
    cb = (cc or "").encode("ascii")[:2].ljust(2, b" ")
    ab = (admin1 or "").encode("ascii")[:255]
    off = len(strtab)
    strtab += bytes([len(nb)]) + nb + cb + bytes([len(ab)]) + ab
    str_index[key] = off
    name_offsets.append(off)

# Build records.
import math as _math
header_size = 16
record_size = 14
records_size = len(deduped) * record_size
str_off = header_size + records_size

buf = bytearray()
buf += b"GCT2"
buf += struct.pack("<III", len(deduped), str_off, 0)
for (lat, lng, _, _, _, pop), off in zip(deduped, name_offsets):
    pop_log = max(0, min(65535, int(round(_math.log10((pop or 0) + 1) * 1000))))
    buf += struct.pack("<iiIH", int(round(lat * 1e5)), int(round(lng * 1e5)), off, pop_log)
buf += strtab

with gzip.open(OUT, "wb", compresslevel=9) as f:
    f.write(buf)
print(f"Raw size: {len(buf):,} bytes ({len(buf)/1024/1024:.2f} MB)")

size = os.path.getsize(OUT)
print(f"Wrote {OUT}: {size:,} bytes ({size/1024/1024:.2f} MB)")
print(f"String table size: {len(strtab):,} bytes")
