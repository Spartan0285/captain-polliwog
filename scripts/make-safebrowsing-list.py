#!/usr/bin/env python3
# Builds the list of dangerous-site hash prefixes that Captain Polliwog reads
# (src/CPSafeBrowsing.m), from Google's Safe Browsing Update API.
#
#   SAFEBROWSING_API_KEY=... scripts/make-safebrowsing-list.py out.list
#
# Run this on a modern Mac, not on the PowerPC one: it downloads a few
# megabytes and needs a Google API key, which is free (Google Cloud console,
# enable "Safe Browsing API", make an API key). The PowerPC side never talks
# to Google at all - it only reads the file this writes, which is why looking
# a site up does not tell anyone which site it was.
#
# The file: "CPSB1", a 4-byte timestamp, a 4-byte count, then that many
# 4-byte big-endian SHA-256 prefixes, sorted. Sorted because the browser
# binary-searches it where it sits in memory.
#
# With no key, --test writes a small file containing a few well-known test
# addresses, which is enough to check that the warning appears.

import base64
import hashlib
import json
import os
import struct
import sys
import time
import urllib.request

API = 'https://safebrowsing.googleapis.com/v4/threatListUpdates:fetch?key=%s'

# The two that matter for a browser: pages that phish, and pages that serve
# malware. The others (unwanted software, potentially harmful applications)
# are mostly about downloads for other platforms.
THREAT_TYPES = ['SOCIAL_ENGINEERING', 'MALWARE']

# Addresses the Safe Browsing documentation publishes for testing.
TEST_URLS = [
    'testsafebrowsing.appspot.com/s/phishing.html',
    'testsafebrowsing.appspot.com/s/malware.html',
    'malware.testing.google.test/testing/malware/',
]


def prefix_of(url):
    """The first four bytes of the SHA-256 of a canonical URL string."""
    return struct.unpack('>I', hashlib.sha256(url.encode('utf-8')).digest()[:4])[0]


def fetch(key):
    """Every 4-byte prefix in a full update of the chosen lists."""
    request = {
        'client': {'clientId': 'captain-polliwog', 'clientVersion': '1.0'},
        'listUpdateRequests': [
            {
                'threatType': threat,
                'platformType': 'ANY_PLATFORM',
                'threatEntryType': 'URL',
                'state': '',                       # empty: send the whole list
                'constraints': {
                    'maxUpdateEntries': 1 << 20,
                    'supportedCompressions': ['RAW'],   # no Rice decoding here
                },
            }
            for threat in THREAT_TYPES
        ],
    }
    body = json.dumps(request).encode('utf-8')
    call = urllib.request.Request(API % key, data=body,
                                  headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(call, timeout=120) as answer:
        response = json.load(answer)

    prefixes = set()
    for update in response.get('listUpdateResponses', []):
        if update.get('responseType') != 'FULL_UPDATE':
            print('warning: %s came back as %s' % (update.get('threatType'),
                                                   update.get('responseType')), file=sys.stderr)
        for addition in update.get('additions', []):
            raw = addition.get('rawHashes', {})
            size = int(raw.get('prefixSize', 4))
            blob = base64.b64decode(raw.get('rawHashes', ''))
            for start in range(0, len(blob) - size + 1, size):
                chunk = blob[start:start + size]
                # Shorter prefixes are widened; longer ones are cut to four.
                chunk = (chunk + b'\0' * 4)[:4]
                prefixes.add(struct.unpack('>I', chunk)[0])
        print('%s: %d prefixes so far' % (update.get('threatType'), len(prefixes)))
    return prefixes


def write(path, prefixes):
    ordered = sorted(prefixes)
    with open(path, 'wb') as out:
        out.write(b'CPSB1')
        out.write(struct.pack('>I', int(time.time())))
        out.write(struct.pack('>I', len(ordered)))
        for value in ordered:
            out.write(struct.pack('>I', value))
    print('%s: %d prefixes, %d bytes' % (path, len(ordered), os.path.getsize(path)))


def main():
    arguments = [a for a in sys.argv[1:] if not a.startswith('-')]
    path = arguments[0] if arguments else 'safebrowsing.list'

    if '--test' in sys.argv:
        write(path, {prefix_of(url) for url in TEST_URLS})
        print('test list: ' + ', '.join(TEST_URLS))
        return

    key = os.environ.get('SAFEBROWSING_API_KEY')
    if not key:
        sys.exit('SAFEBROWSING_API_KEY is not set (or pass --test for a small one).')
    write(path, fetch(key))


main()
