# Updates

Captain Polliwog checks for new versions itself, once a day, and never
installs anything without being asked.

## Why not Sparkle

Sparkle is what a Mac app normally uses, and its "classic" 1.5b6 is the last
release that runs on PowerPC — 1.7 onwards needs 10.7 and the modern
Objective-C runtime. It still doesn't fit:

- It asks Foundation to fetch the feed, and on Tiger and Leopard that is
  TLS 1.0 with a certificate store from 2009. It cannot reach GitHub, or
  anywhere else a release would be kept. Captain Polliwog only reaches the
  modern web at all because it carries its own libcurl, OpenSSL 3 and CA
  bundle, and the updater goes through the same stack.
- 1.5b6 signs updates with DSA, and shows release notes in a WebView, which is
  how CVE-2016-4663 turned an update check into remote code execution. EdDSA
  arrived in Sparkle 1.21, which is 10.7-only.

So the updater here is about 400 lines in `src/CPUpdater.m`, using what the
browser already has.

## How it works

1. **The feed** is `updates/appcast.plist` in this repository, fetched over
   https from `raw.githubusercontent.com` through `CPCurlProtocol`. It is a
   property list because Tiger can parse those natively and cannot parse JSON.
   Each version carries its `url`, `length`, `sha256`, an Ed25519 `signature`
   and plain-text `notes`.
2. **The signature** covers a short manifest, not the archive:

   ```
   captain-polliwog-update-v1
   <version>
   <length>
   <sha256, lowercase hex>
   ```

   Binding the length and digest is what makes the download safe; binding the
   version stops an old signed release being served in place of a new one.
   Ed25519 verification is `EVP_DigestVerify` from the OpenSSL already linked
   in. The public key is compiled into the app.
3. **The download** is streamed to a file by `CPNetworkTask`, never held in
   memory — these machines may only have 256MB. It is then hashed on a
   background thread (a few seconds for 37MB on a G4), the signature checked,
   and only then unpacked with `ditto`. The unpacked bundle must carry our
   bundle identifier and the version the feed promised.
4. **Installing** moves the running app aside, moves the new one into place,
   and leaves a shell command waiting for this process to exit before it
   deletes the old copy and opens the new one. If the folder the app sits in
   is not writable, it says so and leaves the new version for the user to drag
   across rather than asking for a password.

Release notes are plain text, drawn by an `NSTextView`. Nothing from an update
is executed until the user chooses to install it.

## Making a release

The signing key lives at `~/.captain-polliwog/update-signing-key.pem` and must
never enter this repository — anyone holding it can hand every copy of Captain
Polliwog an update of their choosing. Back it up: the public half is compiled
into every build, so losing it means no existing copy can be updated again.

```sh
scripts/generate-update-key.sh        # once, ever; prints the public key
```

Then, per release:

```sh
# 1. Build the app and stage it with the engine frameworks.
scripts/remote-build.sh g4
scripts/install-test-build.sh pbg4 leopard-g4-jit     # also leaves the staged bundle

# 2. Zip the staged bundle as CaptainPolliwog-<version>.zip, with the app at
#    the top level, then sign it into the feed.
scripts/make-appcast.py 0.3 CaptainPolliwog-0.3.zip notes.txt

# 3. Attach the zip to a GitHub release tagged v0.3, and push the feed.
git add updates/appcast.plist && git commit -m "Release 0.3" && git push
```

`make-appcast.py` writes the url as
`<repo>/releases/download/v<version>/<file>`, so the tag and the file name have
to match what was attached.

## Testing an update before publishing

`UPDATE_URL_BASE` points the generated feed somewhere else, and the
`CPUpdateFeed` default points the app at a feed of your choosing. A feed named
in the defaults may be plain http or a local file, because what makes an update
safe to install is its signature, not where it was fetched from — an unsigned
update is refused whatever the source.

```sh
UPDATE_URL_BASE=http://192.168.68.130:8765 scripts/make-appcast.py 0.3 CaptainPolliwog-0.3.zip
ssh pbg4 'defaults write org.captainpolliwog.browser CPUpdateFeed \
    "http://192.168.68.130:8765/appcast.plist"'
```

`CPDebugUpdate` makes the app check at launch and download without the window;
`CPDebugUpdateInstall` goes on to replace the running copy. Both log each step
to the system log (`Captain Polliwog: update checking`, `available`,
`downloading`, `ready to install`).
