#!/bin/sh
# Makes the key that releases are signed with (Ed25519), and prints the public
# half to paste into src/CPUpdater.m.
#
#   scripts/generate-update-key.sh
#
# The private half is written to ~/.captain-polliwog/update-signing-key.pem and
# must never go into this repository: anyone holding it can hand every copy of
# Captain Polliwog an update of their choosing. Keep a backup somewhere safe -
# if it is lost, no existing copy can be updated again, because the public half
# is compiled into them.
set -e

OPENSSL=${OPENSSL:-$(command -v openssl)}
KEY_DIR=$HOME/.captain-polliwog
KEY=$KEY_DIR/update-signing-key.pem

if [ -f "$KEY" ]; then
    echo "$KEY already exists; not replacing it." >&2
    echo "Its public half is:" >&2
else
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
    (umask 077 && "$OPENSSL" genpkey -algorithm ED25519 -out "$KEY")
    chmod 600 "$KEY"
    echo "Wrote $KEY. Back it up, and keep it out of the repository." >&2
fi

# An Ed25519 public key in DER is a 12-byte header and then the 32 key bytes.
"$OPENSSL" pkey -in "$KEY" -pubout -outform DER | tail -c 32 | base64
