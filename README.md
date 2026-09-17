# Captain Polliwog

A web browser for Mac OS X 10.4 Tiger and later, on PowerPC (G3 and up) and Intel.

**Status: 0.1, early development.** The app currently uses the WebKit built into
the OS, which cannot connect to most modern HTTPS sites. The next steps are:

1. Bundled modern TLS (OpenSSL), so HTTPS works on Tiger and Leopard.
2. Tabs, bookmarks, history, downloads and private browsing.
3. A modern WebKit engine ported to Tiger/PowerPC.

## Building

On a Mac running Tiger (Xcode 2.5) or Leopard (Xcode 3.1) with the 10.4u SDK:

    make

This produces `build/Captain Polliwog.app`, a Universal (PowerPC + Intel) binary.

From a modern Mac, `scripts/remote-build.sh [host ...]` copies the sources to
PowerPC Macs over SSH and builds there. `scripts/remote-run.sh host [url]` launches
the app, loads a page, and copies back a snapshot of the window.
