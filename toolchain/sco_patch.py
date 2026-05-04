#!/usr/bin/env python3
"""
Patch a GNU-linked i386 ELF binary to run on SCO OpenServer 5.0.7.

What this does:
  1. Merges multiple PT_LOAD segments into exactly 2:
       LOAD[0] R|E : offset=0 .. start-of-dynamic  (code+interp+hash+text)
       LOAD[1] R|W|E: offset/vaddr starting exactly at PT_DYNAMIC.p_vaddr
  2. Replaces GNU_STACK (or last null/junk PHDR) with PT_NOTE,
     p_filesz=0x1c, p_vaddr=0 (SCO dynamic linker checks this field).
  3. Appends 28 bytes of SCO note data to the file.
  4. Zeroes all p_paddr fields (SCO convention).

Usage: python3 sco_patch.py <input> <output>
"""
import struct, sys, os, stat

def u32(data, off): return struct.unpack_from('<I', data, off)[0]
def u16(data, off): return struct.unpack_from('<H', data, off)[0]

def read_phdr(data, base):
    fields = struct.unpack_from('<IIIIIIII', data, base)
    return list(fields)  # p_type,p_offset,p_vaddr,p_paddr,p_filesz,p_memsz,p_flags,p_align

def write_phdr(data, base, fields):
    struct.pack_into('<IIIIIIII', data, base, *fields)

PT_NULL    = 0
PT_LOAD    = 1
PT_DYNAMIC = 2
PT_INTERP  = 3
PT_NOTE    = 4
PT_PHDR    = 6
PT_GNU_STACK = 0x6474e551

infile  = sys.argv[1]
outfile = sys.argv[2]

with open(infile, 'rb') as f:
    data = bytearray(f.read())

assert data[0:4] == b'\x7fELF', "Not an ELF file"
assert data[4] == 1,            "Not 32-bit ELF"
assert data[5] == 1,            "Not little-endian ELF"

e_phoff     = u32(data, 0x1c)
e_phentsize = u16(data, 0x2a)
e_phnum     = u16(data, 0x2c)

print(f"Input: {infile}")
print(f"PHDRs: {e_phnum} x {e_phentsize} bytes at offset 0x{e_phoff:x}")

phdrs = []
for i in range(e_phnum):
    phdrs.append(read_phdr(data, e_phoff + i * e_phentsize))

print("Current PHDRs:")
type_names = {0:'NULL',1:'LOAD',2:'DYNAMIC',3:'INTERP',4:'NOTE',6:'PHDR',0x6474e551:'GNU_STACK'}
for i, p in enumerate(phdrs):
    nm = type_names.get(p[0], f'0x{p[0]:x}')
    print(f"  [{i}] {nm:12s} off=0x{p[1]:06x} va=0x{p[2]:08x} filesz=0x{p[4]:05x} memsz=0x{p[5]:05x} flags=0x{p[6]:x}")

# Find key segments
dyn_phdr  = next((p for p in phdrs if p[0] == PT_DYNAMIC), None)
phdr_phdr = next((p for p in phdrs if p[0] == PT_PHDR), None)
interp_phdr = next((p for p in phdrs if p[0] == PT_INTERP), None)
loads = [p for p in phdrs if p[0] == PT_LOAD]

assert dyn_phdr,   "No PT_DYNAMIC found"
assert loads,      "No PT_LOAD found"

dyn_vaddr = dyn_phdr[2]
print(f"\nPT_DYNAMIC.p_vaddr = 0x{dyn_vaddr:08x}")

# Find which LOAD contains PT_DYNAMIC (the writable one)
writable = None
for p in loads:
    end = p[2] + p[5]  # p_vaddr + p_memsz
    if p[2] <= dyn_vaddr < end:
        writable = p
        break

assert writable, f"No PT_LOAD covers dynamic at 0x{dyn_vaddr:08x}"
print(f"Writable LOAD: off=0x{writable[1]:x} va=0x{writable[2]:x} filesz=0x{writable[4]:x}")

# Code LOADs = everything else
code_loads = [p for p in loads if p is not writable]

# New LOAD[0]: offset=0, vaddr=first code load's vaddr, covers up to writable
code_loads_sorted = sorted(code_loads, key=lambda p: p[1])  # by p_offset
first_code = code_loads_sorted[0]

# LOAD[1] must start at exactly PT_DYNAMIC.p_vaddr so that _rt_map_so
# computes -0x4c = dyn_vaddr (the SCO dynamic linker uses the second
# LOAD segment's p_vaddr as the effective dynamic_addr).
delta = dyn_vaddr - writable[2]       # bytes from writable LOAD start to .dynamic
new_load1_offset = writable[1] + delta
new_load1_vaddr  = dyn_vaddr
new_load1_filesz = writable[4] - delta
new_load1_memsz  = writable[5] - delta
new_load1_flags  = 7                  # R|W|E (SCO style — native uses 7 not 6)
new_load1_align  = 0x1000

# LOAD[0] covers from offset 0 to just before new LOAD[1]
new_load0_offset = first_code[1]      # should be 0
new_load0_vaddr  = first_code[2]      # should be 0x8048000
new_load0_filesz = new_load1_offset - new_load0_offset
new_load0_memsz  = new_load0_filesz
new_load0_flags  = 5                  # R|E
new_load0_align  = 0x1000

print(f"\nNew LOAD[0]: off=0x{new_load0_offset:x} va=0x{new_load0_vaddr:x} filesz=0x{new_load0_filesz:x}")
print(f"New LOAD[1]: off=0x{new_load1_offset:x} va=0x{new_load1_vaddr:x} filesz=0x{new_load1_filesz:x}")

assert new_load0_filesz > 0, "LOAD[0] filesz would be 0 — dynamic is too early"
assert new_load1_filesz > 0, "LOAD[1] filesz would be 0"
assert new_load1_vaddr % new_load1_align == new_load1_offset % new_load1_align, \
    f"ELF alignment mismatch: vaddr%align=0x{new_load1_vaddr%new_load1_align:x} offset%align=0x{new_load1_offset%new_load1_align:x}"

# SCO note: namesz=4 descsz=12 type=1 name="SCO\0" desc=12 bytes
SCO_NOTE = struct.pack('<III', 4, 12, 1) + b'SCO\x00' + \
           bytes([0x01, 0x00, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
assert len(SCO_NOTE) == 28 == 0x1c

note_file_offset = len(data)
data.extend(SCO_NOTE)
print(f"Appended SCO note at file offset 0x{note_file_offset:x}")

# Build the new PHDR table (keep same slot count, null-pad any extras)
# Desired order: PHDR, INTERP, LOAD0, LOAD1, DYNAMIC, NOTE, [NULL...]
new_phdrs = []

if phdr_phdr:
    p = list(phdr_phdr); p[3] = 0  # zero p_paddr
    new_phdrs.append(p)

if interp_phdr:
    p = list(interp_phdr); p[3] = 0
    new_phdrs.append(p)

new_phdrs.append([PT_LOAD, new_load0_offset, new_load0_vaddr, 0,
                  new_load0_filesz, new_load0_memsz, new_load0_flags, new_load0_align])

new_phdrs.append([PT_LOAD, new_load1_offset, new_load1_vaddr, 0,
                  new_load1_filesz, new_load1_memsz, new_load1_flags, new_load1_align])

if dyn_phdr:
    p = list(dyn_phdr); p[3] = 0
    new_phdrs.append(p)

# PT_NOTE: p_vaddr=0, p_filesz=0x1c — SCO _rt_map_so checks this
new_phdrs.append([PT_NOTE, note_file_offset, 0, 0, 0x1c, 0, 0, 0x1000])

# Pad to original e_phnum with nulls
while len(new_phdrs) < e_phnum:
    new_phdrs.append([PT_NULL, 0, 0, 0, 0, 0, 0, 0])

new_phdrs = new_phdrs[:e_phnum]  # truncate if somehow longer

# Write new PHDR table back into the binary
for i, p in enumerate(new_phdrs):
    write_phdr(data, e_phoff + i * e_phentsize, p)

print("\nNew PHDRs:")
for i, p in enumerate(new_phdrs):
    nm = type_names.get(p[0], f'0x{p[0]:x}')
    print(f"  [{i}] {nm:12s} off=0x{p[1]:06x} va=0x{p[2]:08x} filesz=0x{p[4]:05x} memsz=0x{p[5]:05x} flags=0x{p[6]:x}")

with open(outfile, 'wb') as f:
    f.write(data)

os.chmod(outfile, os.stat(outfile).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
print(f"\nWritten: {outfile}")
