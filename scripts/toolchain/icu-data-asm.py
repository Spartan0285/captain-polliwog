#!/usr/bin/env python3
# Writes ICU's common data as PowerPC Mac OS X assembly, for a static
# libicudata. ICU's own genccode writes .long words in the byte order of the
# machine it runs on, so on little-endian Linux every 4 bytes of big-endian
# data come out reversed and ICU rejects the data (U_INVALID_FORMAT_ERROR).
# Here the words are read big-endian, which is how the PowerPC assembler lays
# them down, so the bytes arrive unchanged.
#   icu-data-asm.py icudt55b.dat icudt55 > icudt55b_dat.S
import struct, sys

data = open(sys.argv[1], 'rb').read()
if data[2:4] != b'\xda\x27' or data[8] != 1:
    sys.exit('%s is not big-endian ICU data' % sys.argv[1])
data += b'\0' * (-len(data) % 4)
symbol = '_%s_dat' % sys.argv[2]
out = sys.stdout
out.write('.globl %s\n\t.const\n\t.balign 16\n%s:\n' % (symbol, symbol))
words = struct.unpack('>%dI' % (len(data) // 4), data)
for i in range(0, len(words), 16):
    out.write('.long ' + ','.join('0x%08X' % w for w in words[i:i + 16]) + '\n')
