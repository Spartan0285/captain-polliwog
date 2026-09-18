# Captain Polliwog: rendering engine plan

*September 2026. Status of the research and experiments behind the next
major step: getting a newer web engine than the one built into Tiger and
Leopard.*

## Where things stand

Captain Polliwog 0.2 is a complete browser shell (tabs, bookmarks, history,
downloads, private browsing, memory budgeting, disk cache) that does all of
its own networking through bundled OpenSSL 3.5, libcurl 8.22 and zlib. What
it does **not** own is the rendering engine: it uses the WebKit that ships
with the OS.

| Machine | System WebKit | Roughly equals | Era |
|---|---|---|---|
| PowerBook G3, Tiger 10.4.11 | 533.19.4 | Safari 4.1.3 | 2010 |
| iBook G4, Leopard 10.5 | 534.50.2 | Safari 5.1 | 2011 |

That engine is now the limit. It lays out and runs pages written for 2010,
so modern sites show missing icons (Wikipedia), broken layouts, or scripts
that fail. On the Pismo, once networking was fixed, most of the remaining
page load time is the engine itself: a repeat visit that downloads nothing
still takes about 6 seconds.

## What changed: upstream WebKit dropped PowerPC's byte order

On **1 August 2026**, upstream WebKit removed big-endian support
(commit 232cebab, bug 320780). `PlatformCPU.h` now contains:

```
#if !CPU(LITTLE_ENDIAN)
#error "Unsupported endian"
```

PowerPC Macs are big-endian, so **no future WebKit will build for them**.
The day after, 32-bit JSValues and the 32-bit ARM JIT were removed as well.
Any "modern WebKit" for these machines is therefore a fork, frozen at a
release branch, whose security fixes we backport ourselves.

The last usable branches:

| Branch | Released | Graphics | Big-endian | Notes |
|---|---|---|---|---|
| **2.52.x** | early 2026 | Cairo | yes | Last with Cairo. Debian ships 2.52.6 on 32-bit big-endian `powerpc` Linux today. |
| 2.54.x | 16 Sep 2026 | Skia only | yes, with patches | Skia does not support big-endian; Fedora carries downstream patches for s390x. |
| 2.56+ | 2027 | Skia | **no** | Will not compile for PowerPC. |

Other facts that shape the plan:

- **Build requirements.** 2.52 needs C++23, GCC 12.2 or newer, and CMake 3.20.
  Apple's GCC 4.0/4.2 cannot build it. MacPorts packages GCC 14 and 15 for
  PowerPC Leopard and Tiger (Iain Sandoe's Darwin branches, with Tiger
  patches), with a modern `ld64` whose branch-island handling copes with
  binaries larger than PowerPC's ±32MB branch range. WebCore is larger
  than that. Whether libstdc++'s C++23 pieces fully work on Darwin 8/9 is
  unconfirmed.
- **No JavaScript JIT.** There has never been a PowerPC JIT for
  JavaScriptCore. JavaScript would run in the C interpreter ("CLoop"),
  roughly 10x slower than JIT modes in published measurements. For
  comparison, TenFourFox's PowerPC JIT was about 41x faster than its own
  interpreter on a G5.
- **Memory.** Current WebKit's web process commonly uses 180-400MB. The
  Pismo's 1GB upgrade is a precondition for anything built on it.
- **The right model already exists.** HaikuWebKit, actively maintained,
  keeps WebKit's single-process "WebKitLegacy" API alive out of tree, and
  uses **curl + OpenSSL** for networking and a native graphics context. That
  is structurally the same as Captain Polliwog. Every upstream port is
  multi-process and GLib- or Windows-based.

## The discovery: a 2018 WebKit already runs inside Captain Polliwog

The iBook's Safari is **Leopard WebKit** (Tobias Netzel's project): WebKit
604.5.7, from Safari 11 in 2018, built for PowerPC Leopard and shipped as
frameworks inside the app bundle. Its regular-expression and CSS engines use
a PowerPC JIT borrowed from TenFourFox; JavaScript itself does not.

Pointing a copy of Captain Polliwog at those frameworks (via `LSEnvironment`
and `DYLD_FRAMEWORK_PATH`, no code changes) worked on the first try on the
iBook:

- **Modern Wikipedia renders correctly.** The logo, menu and search icons that
  were empty boxes on the system engine appear, and the current layout
  (Vector 2022) is used.
- **The whole networking layer works underneath it unchanged.** TLS, cookies,
  cache, redirects: page loaded in 5.5s.
- **Memory: 65MB**, against 54-59MB on the system engine.

This is eight years of engine progress (flexbox, grid, ES2017, fetch,
modern SVG and CSS), available now, on Leopard. It does not run on Tiger.

## Can the 2018 engine run on the PowerBook and Tiger?

Measured on the machines themselves, September 2026.

**The binaries: no, on any OS.** Leopard WebKit's frameworks are built only
for G4 (`ppc7400`, which uses AltiVec) and G5 (`ppc970`). The Pismo's G3 has
no AltiVec, so these exact files cannot run on it even under Leopard. Any
route to the 2018 engine on the Pismo starts with building it from source for
the G3 (`-mcpu=750`).

**The OS: 207 missing functions.** Every function the three frameworks
import from the system (about 1,700, excluding the libraries Leopard WebKit
bundles itself: ICU, SQLite, libxml2, libstdc++, Security) was checked
against everything Tiger 10.4.11 exports on the Pismo. 142 more looked missing at
first but only moved between frameworks from 10.4 to 10.5; a build against the
10.4 SDK resolves those by itself. What remains:

| Kind | Count | What it takes |
|---|---|---|
| `$UNIX2003` / `$INODE64` variants | 18 | Nothing: building for 10.4 picks the old names. |
| Game controllers (IOHID) | 26 | Stubs; gamepad support off. |
| Constants and small calls (accessibility names, window notifications, speech, grammar, input sources, backup exclusion, power assertions, `backtrace`, WebGL extensions) | about 45 | Stubs or constant strings. |
| Objective-C 2.0 runtime (`class_addMethod`, `method_exchangeImplementations`...) | 23 | A shim over Tiger's Objective-C 1 runtime. A known technique. |
| Quartz additions (`CGGradient`, generic colors, font smoothing switches) | 28 | Shims: gradients via Tiger's `CGShading`, the rest mostly no-ops. |
| CommonCrypto | 9 | Implement with the OpenSSL Captain Polliwog already bundles. |
| `CFError`, `CFLocale` preferred languages, proxy keys | about 15 | Small shims. |
| Private CFNetwork (cookie storage, URL cache, request/response accessors) | about 30 | Shims onto the public cookie and URL APIs; Captain Polliwog's own networking already replaces most of the path. |
| CoreText | 17 | Tiger has a private CoreText that exports most of what WebKit calls; only 17 functions are absent. Behaviour may differ: the main risk. |
| Core Animation (`CALayer` and friends) | 22 | Run with accelerated compositing off (a WebKit preference) and supply stub classes so the frameworks load. 3D transforms and some effects fall back or are lost. |

The standard way to do this is to build against the 10.5 SDK with a 10.4
deployment target, so that 10.5-only functions are weakly linked and simply
absent on Tiger, plus a small "Tiger shim" library for the ones WebKit
actually calls. Objective-C class references cannot be weak on Tiger's
runtime, so the Core Animation classes need real (empty) stand-ins.

**Verdict:** plausible, not trivial. There is no sign of a wall. The
two risks worth testing first are text layout on Tiger's private CoreText and
rendering with accelerated compositing turned off.

## Building the 2018 engine ourselves

What Leopard WebKit's own sources show (SourceForge, `604/Sources/Patches_604.5.6.tar.bz2`):

- **Source.** One patch against Apple's WebKit tag `Safari-604.5.6`, which is
  still on WebKit's GitHub, plus small patches for lz4 and OTS. The patch adds
  73,000 lines across 1,352 files, most of them in WebKitLegacy and
  WebCore/platform: it already carries a WebKit written for macOS 10.11 all
  the way back to 10.5. Tiger is one more step down the same road.
- **Build system.** Apple's Xcode projects, with settings keyed on
  `TARGET_MAC_OS_X_VERSION_MAJOR` (1050, 1060...), so a 1040 (Tiger) target
  fits the existing structure. CPU tuning is per architecture
  (`ppc7400` for G4, `ppc64`/`ppc970` for G5); a `ppc` (G3, `-mcpu=750`) build
  is an architecture the build scripts already accept.
- **Toolchain.** Xcode 3.1 on Leopard, with GCC 5/6 plugged in as an Xcode
  compiler (601 and later were built against GCC 6.1's libgcc and libstdc++),
  plus Python 2.7, Ruby 1.9+, Perl 5.10+ and newer flex, which the author
  installed from MacPorts. The published step-by-step instructions stop at
  WebKit 600; 604's have to be reconstructed from the patch.
- **Size.** About 15GB of disk for four architectures. Build time on a
  1.42GHz G4 is unknown but likely many hours per architecture; spreading the
  compile with distcc (which the instructions mention) to a cross compiler on
  a modern Mac would cut that sharply.

## Progress: cross-building 604 on the Mac

All compiling happens on the Apple Silicon Mac, in a Linux VM with a PowerPC
cross toolchain (`scripts/toolchain/`); the old Macs only run the results.
`scripts/toolchain/webkit.sh` configures and builds; it copies the checkout
onto the VM's own disk first, since compiling WebCore through the shared
folder is 13x slower. The
WebKit tree is `Safari-604.5.6` plus Leopard WebKit's patch, built with
WebKit's CMake "Mac" port instead of Xcode, one commit per change on a
`polliwog` branch. Order: reproduce Leopard's G4 build first, then the G3 CPU,
then Tiger.

**JavaScriptCore runs on the iBook** (17-18 September 2026). A full build takes
under 4 minutes on the Mac. It passes a modern-JavaScript smoke test
(classes, async/await, generators, typed arrays, template strings, Intl with
all 683 ICU locales). Speed against Leopard WebKit's own JavaScriptCore,
same `jsc` program, iBook G4 1.42GHz:

| Test | Our build (GCC 6.5) | Leopard WebKit |
|---|---|---|
| fib(25) | 78 ms | 69 ms |
| sort 100k numbers | 1445 ms | 1303 ms |
| build a 200k string | 354 ms | 324 ms |
| 20k regex matches (PowerPC regex JIT) | 75 ms | 75 ms |
| JSON round trips | 130 ms | 112 ms |
| 200k small objects | 138 ms | 124 ms |

About 10% behind, with G4 tuning (`-mtune=7450`) not yet tried.

What reproducing the Xcode build through CMake took:

- **Feature set.** The Xcode build passes `-DENABLE_X` only for what
  `FeatureDefines.xcconfig` turns on and lets `wtf/FeatureDefines.h` decide
  the rest; CMake forces every feature. `Tools/polliwog/probe-leopard-features.sh`
  asks the preprocessor what Leopard's build ends up with, and
  `OptionsMac.cmake` matches it for 10.4/10.5 targets (28 features off,
  13 on). This also turns off the remote Web Inspector, which needs
  libdispatch (10.6+).
- **Leopard's source choices.** The generic, thread-based `WorkQueue` instead
  of the libdispatch one; `libauto` on 10.5; the PowerPC assembler, which
  powers the regular-expression JIT (the JavaScript JIT stays off, so
  JavaScript runs in the C interpreter, as in Leopard WebKit).
- **Compiler settings Xcode implies.** `gnu++14` rather than `c++14`
  (Leopard's `math.h` hides `llround` in strict mode), `-fobjc-exceptions`,
  and ICU without symbol renaming.
- **`mig`.** Linux has no Mach interface generator; the four files it makes
  were generated once with Leopard's own `mig` on the iBook and are kept in
  the tree.
- **One shared C++ runtime.** Like Leopard WebKit, every image uses one
  bundled `libstdc++.6.dylib` and `libgcc_s.1.dylib`. With a static runtime
  in each library, `std::call_once` crashed: its state lives in emulated
  thread-local storage, which is per copy of libgcc.
- **ICU 55.2** is one `libicucore.dylib`, as in Leopard WebKit. ICU's
  cross build reversed every 4 bytes of its data (its `genccode` writes words
  in the build machine's byte order); `scripts/toolchain/icu-data-asm.py`
  writes the data correctly.
- **Bugs in WebKit's Mac CMake files**, which Apple never used for shipping:
  case-sensitive framework names, stale source lists, a list-valued linker
  flag.

**The whole engine runs in Captain Polliwog on the iBook** (18 September
2026). JavaScriptCore, WebCore and WebKitLegacy build from source on the Mac
(about 40 minutes from clean) and are packaged as Leopard WebKit packages them
(`scripts/toolchain/package-webkit.sh`: the three frameworks with their system
install names and re-exports, their resources, and the bundled libraries).
Captain Polliwog loads them unchanged through `DYLD_FRAMEWORK_PATH`
(`scripts/engine-run.sh`). Modern Wikipedia renders correctly, fetched
entirely through Captain Polliwog's own networking: page load 5.9s, 73MB.

What WebCore and WebKitLegacy took, beyond the JavaScriptCore work above:

- **The libraries Leopard WebKit bundles**, built for the G3 and Tiger so every
  variant can share them: SQLite 3.53.4 (Leopard's 3.4 is too old),
  libxml2 2.15.4 and libxslt 1.1.45 (Leopard's 2.6 is too old; one WebCore
  callback needed libxml2 2.12's const signature), and OTS 6.1.1, the web-font
  sanitizer, with Leopard WebKit's unique-font-name change; it also decodes
  WOFF2. OTS's Makefile hard-codes the Linux `ar`, whose archives ld64 reads
  only partly, so it is archived with Apple's.
- **WebGL** as in Leopard WebKit, with ANGLE's shader translator.
- **A Growl stand-in.** Leopard WebKit shows web notifications through Growl,
  which it bundles; ours reports Growl as absent, as Leopard WebKit behaves
  on a Mac without it.
- **Compiler modes Xcode implies.** WebKitLegacy's CMake built every file as
  Objective-C++; GCC 6's Objective-C++ rejects C++14 lambda init-captures and
  its `.m` files declare C functions without `extern "C"`, so `.cpp` stays
  C++ and `.m` Objective-C, as Xcode builds them.
- **Re-exports.** Applications linked against the system WebKit bind some
  Objective-C runtime functions through WebKit, which re-exports WebCore,
  which re-exports libobjc. Without them the app stopped at launch.
- **WebCore is bigger than PowerPC's branch reach.** Its 30MB of code needs
  branch islands. GCC puts cold code and static initializers in sections of
  their own, which the linker now folds into `__text`, where islands work.
  And cctools-port's ld64 got islands wrong for branches with an offset
  (GCC's epilogues branch to `restGPRx+60`, libgcc's restore of r28-r31):
  the branch kept its offset past the island, and the island dropped it.
  The first made a function loop forever at launch, the second silently
  restored registers a function had never saved. Fixed in the linker
  (`scripts/toolchain/ld64-branch-island-addend.patch`).

**Making modern sites work** (18 September 2026). A survey of 19 sites
(`scripts/site-survey.sh`, which records load time, memory, JavaScript
errors, stalls and crashes per site) found four problems common to many:

- **WebCore saw none of our response headers.** It reads them from the
  CFNetwork message behind a response, and responses made by an
  NSURLProtocol have none, so every cross-origin check failed (GitHub
  loaded no styles) and no security or caching header applied. WebCore now
  falls back to `-allHeaderFields`.
- **No `Accept-Language` header.** The system's networking adds it and ours
  replaces that networking; without it eBay answered a search with an error
  page and bot checks singled the browser out.
- **No `window.performance`.** Leopard WebKit leaves Web Timing off for
  10.5; Google Search stops at the missing variable. Now on.
- **Modern JavaScript syntax.** One unsupported construct makes a whole
  script fail to parse. JavaScriptCore now has optional chaining (`?.`),
  nullish coalescing (`??`), object rest/spread (already in 604 behind a
  flag, which Safari 11.1 turned on), optional catch binding and
  `globalThis`: `engine/tests/es2020.js` passes all 43 checks, and the
  interpreter's speed is unchanged.

Two crashes came from Captain Polliwog bundling upstream ICU rather than
Apple's: WebKit's caret rules use an Apple-only option (`!!RINoChain`), and
the failed rule set left a null iterator that typing into a password field
or clicking into some text fields dereferenced.

Next: move the engine from a test copy into the app proper (loaded only on
Leopard with a G4, with the system engine as a fallback), re-verify every
shell feature on it and measure it against the system engine; then the G3
build and the Tiger port.

## Options

| | What | Tiger | Leopard | Effort | Engine age | Main risk |
|---|---|---|---|---|---|---|
| **1** | **Bundle Leopard WebKit 604** | no | **yes** | weeks | 2018 | Unpatched since 2018 |
| 2 | Port Leopard WebKit 604 to Tiger | yes | yes | weeks to months | 2018 | 207 missing functions; text layout and compositing are the risks |
| **3** | **Fork WebKit 2.52 as a new port** (HaikuWebKit model) | goal | yes | many months | 2026 | Toolchain, size of the port, security upkeep |
| 4 | Stay on the system engine | yes | yes | none | 2010-11 | Sites keep breaking |
| - | Gecko (Aquafox/TenFourFox) | - | - | - | - | A different browser, not an engine we can embed. Useful as a speed yardstick: it has the only PowerPC JavaScript JIT. |

## Recommendation

Do option 1 now, and start option 3 as a sequence of spikes, each with a
clear go/no-go, so no month of work is spent before the risky parts have
been tested on these machines.

### Stage 1: Leopard WebKit 604 as the Leopard engine (weeks)

1. **Build from source, not borrowed binaries.** Leopard WebKit's source is on
   SourceForge. Building it ourselves lets us ship it under the LGPL properly,
   choose G3/G4/G5 variants, and patch it.
2. **Bundle it** inside Captain Polliwog, loaded only on 10.5; Tiger keeps
   the system engine. Replace the `LSEnvironment` trick with proper install
   names.
3. **Re-verify every shell feature on the new engine:** cookies, private
   browsing (604's own private mode differs), downloads, the memory budget
   calls (`setCacheModel:`, `WebCache`), tab discarding, context menus.
4. **Measure** load time, memory and scrolling against the system engine on
   the iBook, and on the Pismo booted into its Sorbet Leopard partition, if
   Leopard WebKit's G3 build runs there.
5. **Be honest about security.** 604 has eight years of unfixed engine
   vulnerabilities. That is still better than the system's 2010-11 engine,
   but it should be stated plainly in the app, with plug-ins kept off.

### Stage 2: spikes toward a 2026 engine (option 3)

Each spike runs on the iBook first; each ends with a decision.

| Spike | Question it answers | Go if |
|---|---|---|
| **A. Toolchain** | Can GCC 14/15 + modern ld64 build large C++23 code for `powerpc-apple-darwin9`, and `darwin8`? | A C++23 test program using threads, atomics, `<format>` and exceptions runs on both Macs. |
| **B. JavaScriptCore** | Does 2.52's JSCOnly port build and run for big-endian PowerPC Darwin, and how fast is CLoop on a G4 and a G3? | It passes a core test subset, and a JetStream-style run is within reach of usable. |
| **C. First paint** | Can WebCore + an out-of-tree WebKitLegacy (as HaikuWebKit does) draw a page into an NSView through Cairo's Quartz backend, with curl networking? | A static page renders in a Captain Polliwog window. |
| **D. Real sites** | Memory and speed on the target site list (webmail, shopping, Wikipedia, DuckDuckGo). | Better than Leopard WebKit 604 on the sites that matter. |

If spike B shows CLoop JavaScript is unusable on these CPUs, the fallback is
to invest in speed rather than in a newer engine: an offlineasm PowerPC
backend for the LLInt interpreter, and TenFourFox's PowerPC MacroAssembler
for the regular-expression JIT, as Leopard WebKit did.

### Stage 3: living with a frozen engine

Whatever engine we ship will not get upstream fixes. Plan for a regular,
selective backport of security fixes from upstream and from the distributions
that still build for big-endian (Debian ships 2.52 on 32-bit PowerPC Linux).

## What this means for the machines

- **iBook G4 (Leopard):** a large, near-term improvement from Stage 1.
- **PowerBook G3 (Tiger):** stays on the 2010 engine until Stage 2 succeeds on
  Tiger, unless it runs Leopard from its Sorbet Leopard partition. Its 1GB
  RAM upgrade matters for any newer engine.
- **JavaScript-heavy sites** (webmail, big shopping sites) will be slow on
  any WebKit on these CPUs, because none has a PowerPC JavaScript JIT. Reading,
  searching, reference sites and simpler shops are the realistic sweet spot,
  especially on the G3.

## Sources

- WebKit commit removing big-endian: github.com/WebKit/WebKit/commit/232cebabc1f3c9c0e7abfd5bf6a173e5aae8329a (bug 320780)
- Build requirements: Source/cmake/OptionsCommon.cmake, WebKitCommon.cmake; docs.webkit.org GCC requirement policy
- Cairo removal: commit 803415e3 (bug 306269); Skia big-endian: bug 312677; Fedora webkitgtk.spec
- Debian big-endian builds: buildd.debian.org/status/package.php?p=webkit2gtk&suite=sid
- HaikuWebKit: codeberg.org/haiku/haikuwebkit
- MacPorts GCC on PowerPC: macports-ports lang/gcc15 Portfile; github.com/iains/darwin-xtools
- JSC tiers: webkit.org/blog/10308/speculation-in-javascriptcore/
- TenFourFox IonPower: tenfourfox.blogspot.com/2015/06/mission-accomplished-ionpower-kicks.html
- Leopard WebKit: sourceforge.net/projects/leopard-webkit/
- Measurements: this repository, `scripts/measure-cache.sh` and the experiment above.
