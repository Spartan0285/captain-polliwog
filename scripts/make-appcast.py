#!/usr/bin/env python3
# Adds a release to the update feed and signs it.
#
#   scripts/make-appcast.py 0.3 build/CaptainPolliwog-0.3.zip [notes.txt]
#
# The zip must be the one that will be published: the feed binds its length
# and its SHA-256, and Captain Polliwog will not install anything whose bytes
# do not match. The signature is made with ~/.captain-polliwog/update-signing-key.pem
# (scripts/generate-update-key.sh); nothing here ever reads the key twice or
# writes it anywhere.
#
# Publishing a release, once the zip is attached to a GitHub release:
#   scripts/make-appcast.py 0.3 CaptainPolliwog-0.3.zip notes.txt
#   git add updates/appcast.plist && git commit && git push

import hashlib
import os
import plistlib
import subprocess
import sys
import tempfile

REPO = 'https://github.com/Spartan0285/captain-polliwog'
FEED = 'updates/appcast.plist'
KEY = os.path.expanduser('~/.captain-polliwog/update-signing-key.pem')
MINIMUM_SYSTEM = '10.4'


def sign(manifest):
    """Ed25519 over the manifest, base64, via openssl."""
    openssl = os.environ.get('OPENSSL', 'openssl')
    with tempfile.TemporaryDirectory() as scratch:
        message = os.path.join(scratch, 'manifest')
        out = os.path.join(scratch, 'signature')
        with open(message, 'w') as f:
            f.write(manifest)
        subprocess.run([openssl, 'pkeyutl', '-sign', '-inkey', KEY,
                        '-rawin', '-in', message, '-out', out], check=True)
        signature = open(out, 'rb').read()
    assert len(signature) == 64, len(signature)
    import base64
    return base64.b64encode(signature).decode('ascii')


def main():
    if len(sys.argv) < 3:
        sys.exit('usage: make-appcast.py VERSION ZIP [NOTES.txt]')
    version, archive = sys.argv[1], sys.argv[2]
    notes = open(sys.argv[3]).read().strip() if len(sys.argv) > 3 else ''

    if not os.path.exists(KEY):
        sys.exit('%s is missing: run scripts/generate-update-key.sh first.' % KEY)

    length = os.path.getsize(archive)
    digest = hashlib.sha256(open(archive, 'rb').read()).hexdigest()
    manifest = 'captain-polliwog-update-v1\n%s\n%d\n%s\n' % (version, length, digest)

    item = {
        'version': version,
        'minimumSystemVersion': MINIMUM_SYSTEM,
        # UPDATE_URL_BASE points the feed somewhere else, for testing an
        # update before the release exists.
        'url': '%s/%s' % (os.environ.get('UPDATE_URL_BASE',
                                         '%s/releases/download/v%s' % (REPO, version)),
                          os.path.basename(archive)),
        'length': length,
        'sha256': digest,
        'signature': sign(manifest),
    }
    if notes:
        item['notes'] = notes

    feed = {'feed': 'captain-polliwog', 'versions': []}
    if os.path.exists(FEED):
        with open(FEED, 'rb') as f:
            feed = plistlib.load(f)
    feed['versions'] = [v for v in feed.get('versions', []) if v.get('version') != version]
    feed['versions'].append(item)
    feed['versions'].sort(key=lambda v: [int(p) for p in str(v['version']).split('.')])

    os.makedirs(os.path.dirname(FEED), exist_ok=True)
    with open(FEED, 'wb') as f:
        plistlib.dump(feed, f)
    print('%s: %s, %d bytes, sha256 %s' % (FEED, version, length, digest[:16] + '...'))
    print('signed with %s' % KEY)


main()
