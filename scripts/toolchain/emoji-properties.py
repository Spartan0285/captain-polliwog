#!/usr/bin/env python3
# Writes WebKit's Source/JavaScriptCore/yarr/YarrEmojiProperties.h: the
# Unicode emoji properties for \p{...} in regular expressions, which the ICU
# Captain Polliwog bundles (55) predates. The ranges come from the ICU in
# macOS, run on a current Mac.
#   Usage: scripts/toolchain/emoji-properties.py path/to/YarrEmojiProperties.h
import ctypes, sys

icu = ctypes.CDLL('/usr/lib/libicucore.dylib')
icu.u_getPropertyEnum.argtypes = [ctypes.c_char_p]
icu.u_getPropertyEnum.restype = ctypes.c_int
icu.u_hasBinaryProperty.argtypes = [ctypes.c_int, ctypes.c_int]
icu.u_hasBinaryProperty.restype = ctypes.c_byte
version = (ctypes.c_char * 4)()
icu.u_getUnicodeVersion(version)
version = '.'.join(str(b) for b in bytearray(version)[:3])

PROPERTIES = [('Emoji', 'Emoji'), ('Emoji_Presentation', 'EPres'), ('Emoji_Modifier', 'EMod'),
              ('Emoji_Modifier_Base', 'EBase'), ('Emoji_Component', 'EComp'),
              ('Extended_Pictographic', 'ExtPict'), ('Regional_Indicator', 'RI')]

out = ['/*',
       ' * Unicode emoji properties for \\p{...} in regular expressions. The ICU that',
       ' * Captain Polliwog bundles (55) predates them; these ranges are Unicode %s,' % version,
       ' * written by Captain Polliwog\'s scripts/toolchain/emoji-properties.py from the',
       ' * ICU in macOS. Unicode data: Unicode License v3, (c) Unicode, Inc.',
       ' */', '', '#pragma once', '', 'namespace JSC { namespace Yarr {', '',
       'struct EmojiPropertyTable {', '    const char* name;', '    const char* alias;',
       '    const UChar32 (*ranges)[2];', '    unsigned count;', '};', '']
tables = []
for name, alias in PROPERTIES:
    property = icu.u_getPropertyEnum(name.encode())
    ranges, start = [], None
    for c in range(0x110000):
        has = icu.u_hasBinaryProperty(c, property)
        if has and start is None:
            start = c
        elif not has and start is not None:
            ranges.append((start, c - 1))
            start = None
    if start is not None:
        ranges.append((start, 0x10FFFF))
    variable = 'emoji' + name.replace('_', '') + 'Ranges'
    tables.append((name, alias, variable, len(ranges)))
    out.append('static const UChar32 %s[][2] = {' % variable)
    line = '   '
    for first, last in ranges:
        item = ' { 0x%X, 0x%X },' % (first, last)
        if len(line) + len(item) > 100:
            out.append(line)
            line = '   '
        line += item
    out += [line, '};', '']
out.append('static const EmojiPropertyTable emojiPropertyTables[] = {')
out += ['    { "%s", "%s", %s, %d },' % table for table in tables]
out += ['};', '', '} } // namespace JSC::Yarr', '']
open(sys.argv[1], 'w').write('\n'.join(out))
