#!/usr/bin/env python3
# Builds the app icon from Resources/AppIcon.png.
#
#   scripts/make-icns.py [source.png] [out.icns]
#
# Mac OS X 10.4 reads only the classic icon types: three colour channels,
# run-length encoded, with the alpha channel alongside as a separate mask
# (16, 32, 48 and 128 pixels). 10.5 adds PNG at 256 and 512. iconutil writes
# only the PNG types, and Tiger shows a blank icon for those, so the classic
# ones are written here.
#
# sips does the resizing; the rest is this file.

import os
import struct
import subprocess
import sys
import tempfile
import zlib

CLASSIC = [(16, b'is32', b's8mk'), (32, b'il32', b'l8mk'),
           (48, b'ih32', b'h8mk'), (128, b'it32', b't8mk')]
PNG_TYPES = [(256, b'ic08'), (512, b'ic09')]


def read_png(path):
    """The pixels of an 8-bit PNG, as (width, height, channels, bytes)."""
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    pos, idat = 8, b''
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b'IHDR':
            width, height, depth, colour, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and not interlace, (path, depth, interlace)
            channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
        elif kind == b'IDAT':
            idat += body
        elif kind == b'IEND':
            break
        pos += 12 + length

    raw = zlib.decompress(idat)
    stride = width * channels
    out, previous, pos = bytearray(), bytearray(stride), 0
    for _ in range(height):
        filter_type = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            upleft = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                line[i] = (line[i] + left) & 0xff
            elif filter_type == 2:
                line[i] = (line[i] + up) & 0xff
            elif filter_type == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xff
            elif filter_type == 4:
                estimate = left + up - upleft
                dl, du, dul = abs(estimate - left), abs(estimate - up), abs(estimate - upleft)
                nearest = left if dl <= du and dl <= dul else up if du <= dul else upleft
                line[i] = (line[i] + nearest) & 0xff
        out += line
        previous = line
    return width, height, channels, bytes(out)


def compress(channel):
    """ICNS run-length encoding: literal runs of 1-128, repeats of 3-130."""
    out, i, n = bytearray(), 0, len(channel)
    while i < n:
        run = 1
        while run < 130 and i + run < n and channel[i + run] == channel[i]:
            run += 1
        if run >= 3:
            out.append(0x80 + run - 3)
            out.append(channel[i])
            i += run
            continue
        # Literals, up to 128, ending where a run of three starts.
        start = i
        while i < n and i - start < 128:
            if i + 2 < n and channel[i] == channel[i + 1] == channel[i + 2]:
                break
            i += 1
        out.append(i - start - 1)
        out += channel[start:i]
    return bytes(out)


def element(kind, data):
    return kind + struct.pack('>I', len(data) + 8) + data


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else 'Resources/AppIcon.png'
    output = sys.argv[2] if len(sys.argv) > 2 else 'Resources/CaptainPolliwog.icns'
    elements = []

    with tempfile.TemporaryDirectory() as scratch:
        for size, colour_type, mask_type in CLASSIC + [(s, t, None) for s, t in PNG_TYPES]:
            scaled = os.path.join(scratch, '%d.png' % size)
            subprocess.run(['sips', '-s', 'format', 'png', '-z', str(size), str(size),
                            source, '--out', scaled],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if mask_type is None:
                elements.append(element(colour_type, open(scaled, 'rb').read()))
                continue

            width, height, channels, pixels = read_png(scaled)
            assert (width, height) == (size, size), (scaled, width, height)
            assert channels == 4, (scaled, channels)
            planes = [bytes(pixels[c::4]) for c in range(3)]
            body = b''.join(compress(plane) for plane in planes)
            if colour_type == b'it32':
                body = b'\0\0\0\0' + body  # 128x128 carries four leading zeros
            elements.append(element(colour_type, body))
            elements.append(element(mask_type, bytes(pixels[3::4])))

    body = b''.join(elements)
    open(output, 'wb').write(b'icns' + struct.pack('>I', len(body) + 8) + body)
    print('%s: %d elements, %d bytes' % (output, len(elements), len(body) + 8))


main()
