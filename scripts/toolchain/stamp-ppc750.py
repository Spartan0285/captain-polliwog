#!/usr/bin/env python3
"""Marks a PowerPC Mach-O binary as running on a G3.

Apple's libWebKitSystemInterfaceLeopard.a is built for the G4, and the
linker raises the whole output to match the highest CPU it was given: our
WebKitLegacy came out stamped ppc7400 even though every instruction in it
is plain PowerPC. dyld then refuses to load it on a G3 - silently, falling
back to the system WebKit, which is a very confusing way to find out.

This rewrites the CPU subtype to ppc750. It refuses to do so if the binary
actually contains an AltiVec instruction, which is checked by the caller
(package-webkit.sh) with otool, since the only AltiVec in that library is
in cuCrlVerify, a certificate-revocation helper nothing here links.

Usage: stamp-ppc750.py <binary>...
"""
import struct
import sys

MH_MAGIC = 0xFEEDFACE          # 32-bit, big-endian on PowerPC
CPU_TYPE_POWERPC = 18
CPU_SUBTYPE_POWERPC_750 = 9

def stamp(path):
    with open(path, "r+b") as binary:
        header = binary.read(12)
        if len(header) < 12:
            return "too short"
        magic, cputype, cpusubtype = struct.unpack(">III", header)
        if magic != MH_MAGIC:
            return "not a big-endian 32-bit Mach-O"
        if cputype != CPU_TYPE_POWERPC:
            return "not PowerPC"
        if cpusubtype == CPU_SUBTYPE_POWERPC_750:
            return "already ppc750"
        binary.seek(8)
        binary.write(struct.pack(">I", CPU_SUBTYPE_POWERPC_750))
        return "ppc%d -> ppc750" % cpusubtype

if __name__ == "__main__":
    for path in sys.argv[1:]:
        print("%s: %s" % (path.split("/")[-1], stamp(path)))
