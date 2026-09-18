# Captain Polliwog

A web browser for Mac OS X 10.4 Tiger and later, on PowerPC (G3 and up) and Intel.

**Status: 0.2, early development.** The app renders with the WebKit built into
the OS, but does its own networking: every https request goes through a bundled
OpenSSL 3, libcurl and zlib, because the TLS in Tiger and Leopard stops at
TLS 1.0 and cannot reach most sites any more. Current Wikipedia and DuckDuckGo
load on a 500MHz PowerBook G3 with 256MB of RAM, in about 53MB of memory.

Plain http goes through the same stack: Tiger and Leopard try a site's IPv6
address first and wait about fifteen seconds for it to fail on networks
without IPv6, where libcurl tries both at once.

Also in place: tabs (background tabs give up their pages beyond a memory
budget), bookmarks with folders and Safari import, history, downloads that
stream straight to disk, and a disk cache that lets a repeat visit skip the
network entirely.

Private browsing records no history, writes nothing to the disk cache, and
removes the cookies a private session set when it ends.

Next: a modern WebKit engine ported to Tiger/PowerPC.

## Building

The bundled libraries are built once per architecture, on a PowerPC Mac with
Perl 5.10+ available (OpenSSL's Configure rejects the Perl 5.8 that Tiger and
Leopard ship). With the source tarballs in `$HOME`:

    scripts/build-deps.sh ppc
    scripts/build-deps.sh i386

Then, on a Mac running Tiger (Xcode 2.5) or Leopard (Xcode 3.1) with the 10.4u
SDK:

    make

This produces `build/Captain Polliwog.app`, a Universal (PowerPC + Intel) binary.

From a modern Mac, `scripts/remote-build.sh [host ...]` copies the sources to
PowerPC Macs over SSH and builds there. `scripts/remote-run.sh host [url]` launches
the app, loads a page, and copies back a snapshot of the window.

## License

Captain Polliwog's own code is under the [Mozilla Public License 2.0](LICENSE).
Bundled third-party components keep their own licenses.
