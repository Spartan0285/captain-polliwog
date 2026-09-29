#!/usr/bin/env python3
"""Parse the JavaScript that lives inside Objective-C string literals.

CPYouTubeFormats builds two scripts out of @"..." fragments, one per line.
A misplaced brace in there is invisible at compile time and shows up as a
feature that silently does nothing on a machine across the room, so this
pulls them back out and runs them past a real parser.

Usage: scripts/check-embedded-js.py        (needs node)
"""
import re, subprocess, sys, tempfile, os

SOURCE = os.path.join(os.path.dirname(__file__), '..', 'src', 'CPYouTubeFormats.m')

def fragments(text):
    out = []
    for line in text.split('\n'):
        m = re.match(r'\s*(?:return\s+)?@"(.*)"(;?)\s*$', line)
        if m:
            t = m.group(1).replace('\\\\', '\x00').replace('\\"', '"').replace('\x00', '\\')
            out.append(t)
    return ''.join(out)

def main():
    src = open(SOURCE).read()
    blocks = {
        'CPResolveScript': src[src.index('static NSString *CPResolveScript'):
                               src.index('\nstatic NSString * const CPPollScript')],
        'CPPollScript': src[src.index('static NSString * const CPPollScript'):
                            src.index('// One resolve in flight')],
    }
    failed = 0
    for name, block in blocks.items():
        js = fragments(block).replace('" CP_INNERTUBE_CLIENT_VERSION "', '1.65.10')
        if not js.strip():
            print('%-18s NOTHING EXTRACTED' % name); failed += 1; continue
        with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as f:
            f.write(js); path = f.name
        r = subprocess.run(['node', '--check', path], capture_output=True, text=True)
        os.unlink(path)
        if r.returncode == 0:
            print('%-18s ok  (%d characters)' % (name, len(js)))
        else:
            print('%-18s SYNTAX ERROR' % name)
            print('   ' + r.stderr.strip().split('\n')[-1])
            failed += 1
    return 1 if failed else 0

if __name__ == '__main__':
    sys.exit(main())
