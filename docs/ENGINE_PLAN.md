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

**Catching up with 2020s JavaScript** (18 September 2026). GitHub's front
page loads 67 JavaScript modules; 51 parsed. Each construct below made
whole scripts fail somewhere, and each now has a test in `engine/tests`:

- **The response headers, again.** WebCore's fallback to `-allHeaderFields`
  was not enough: Leopard's Foundation hands WebKit a response rebuilt from
  the CFNetwork response underneath ours, and a subclass's fields don't
  survive that. Captain Polliwog now builds its responses on a real
  CFNetwork HTTP message (`CPCurlProtocol.m`); GitHub's 27 cross-origin
  failures went to none.
- **Class fields and private members** (ES2022). As upstream JSC does it:
  a class with fields gets a generated initializer function whose source
  is the class body; compiling it parses only the recorded field
  positions; constructors run it on entry, or after `super()` returns.
  Private names (`#x`) are hidden constants in the class scope holding a
  symbol made per class evaluation, and `obj.#x` is `obj[that symbol]`,
  which gives scoping, closures and nesting for free but no brand check.
  Also static blocks.
- **Smaller syntax.** Logical assignment (`??=`, `||=`, `&&=`), numeric
  separators, `import.meta`, and `await` right after a unary operator
  (`return void await x`), which 604 read as an identifier.
- **Regular expressions.** Named groups (`(?<name>)`, `\k<name>`,
  `match.groups`, `$<name>`), Unicode property escapes (`\p{L}`, with the
  sets from ICU), and the `s` flag. Lookbehind is still missing.
- **The platform.** User Timing and Resource Timing (`performance.mark`,
  which Safari 11 shipped on), import maps (Safari 16.4; GitHub loads React
  through one), and `Resources/polyfills.js`, which the app runs in every
  frame before the page's scripts: AbortController, IntersectionObserver,
  ResizeObserver, `Array.prototype.flat`, `Promise.prototype.finally`,
  `structuredClone`, `queueMicrotask`, Intl additions and more, each only
  where missing.

**Modern CSS, and async generators** (19 September 2026). Apple's home
page stacked its navigation and jammed its buttons together. It needed
`display: contents` (in 604, switched off; the app now turns it on),
`gap` in flexbox, `column-gap` in grid, `padding-block`/`-inline` with
`var()`, `:has()` and `overflow: clip`; all are in, with checks in
`engine/tests/css-modern.html`. `:has()` is matched by walking the
element's descendants (or following siblings) with each argument anchored
back to it; elements it matched are restyled when anything inside them
changes, which is cheap because only those elements are flagged.

Wikipedia ran without its scripts because MediaWiki refuses browsers that
can't parse `async function*`. Async generators (ES2018) are built the way
604 already builds async functions: the body is a generator whose `await`s
and `yield`s both suspend it, a `yield` marks itself on the generator
object first, and `builtins/AsyncGeneratorPrototype.js` drives the body,
queues `next`/`return`/`throw` requests, and does `yield*` delegation.
`for await` asks `@getAsyncIterator` for the iterator (wrapping a plain
iterable's iterator when there is no `Symbol.asyncIterator`) and awaits
each result. `SourceParseMode` grew from 16 to 32 bits for the three new
modes. Tests in `engine/tests/async-generators.js`.

Also on 19 September:
- **The module loader raced.** A module whose dependency another request was
  already loading waited only for that dependency to be parsed, so imports
  that shared modules could link before a dependency's own dependencies had
  resolved ("undefined is not an object"). GitHub loads React this way.
  Linking now first waits until everything reachable is ready
  (`requestSatisfyAll` in `ModuleLoaderPrototype.js`; test in
  `engine/tests/concurrent-imports`).
- **BigInt literals** (`10n`) read as their number, so scripts holding them
  parse; the BigInt stand-in still tells feature tests there is no BigInt.
- **Polyfills:** `performance.measure(name, { start, end })`, constructable
  style sheets (`new CSSStyleSheet()`, `adoptedStyleSheets`), and
  `Intl.NumberFormat` units and compact notation. Speedometer 3.1's Web
  Components and Charts workloads failed without the last two.
- **Debugging:** with `CPDebugLog` on, the app logs the stack of every
  uncaught page error, and the URL of every failed `fetch`.
- **Tuning:** the G4 build schedules for the 7447/7450 core (`-mtune=7450`)
  while still running on the 7400.
- **Speedometer 3.1** is served from a local copy (`browserbench.org` code,
  one added line that posts the score back). Two engine problems it found:
  - `JSON.stringify` took every key a Proxy's `ownKeys` listed. The spec
    keeps only enumerable own properties, and Chart.js's option resolvers
    list every default, so serializing one walked the whole defaults tree
    without end: minutes of CPU and a gigabyte of memory.
  - Text with `font-variant-ligatures: none` or `font-feature-settings`
    (editors, code views) went down the complex text path, several times
    slower on a G4. On 10.5 the simple path does no kerning or ligatures
    anyway, so settings that only turn features off now stay on it.
    TipTap went from 21.9 s to 3.4 s an iteration.

A lesson from the way: `CommonIdentifiers.h` and `BuiltinNames.h` are
compiled into WebCore, so adding a name to either shifts what WebCore reads
(`Document.prototype` came back undefined). After changing them, rebuild
everything, not just JavaScriptCore.

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

## 19 September: the PowerPC JIT, and what Speedometer really measures

JavaScriptCore now has a **PowerPC baseline JIT** (patches 0048-0052): an
offlineasm PPC backend so the LLInt runs as PowerPC code, a new assembler and
macro assembler for the JIT, and the big-endian work that goes with them.
It is built by the `leopard-g4-jit` variant; `leopard-g4` still ships the
interpreter.

Big-endian rules learned the hard way, all of them bugs first:

- A C function returns an `EncodedJSValue` **tag first**, in r3, while JS code
  returns the payload there. `setupResults` swaps; `setupResultsFromJSCall`
  (a JS getter's result) does not; the native call thunks and the VM entry
  swap.
- JSValue **arguments** to C go tag first (`JSVALUE_ARGUMENT_WORDS`).
- The **callee** and **argument count** call frame slots keep their payload at
  +4 (`callFrameHeaderOffset`).
- Leopard WebKit keeps the **integer typed arrays little-endian** even on a
  big-endian Mac, so the JIT uses `lhbrx`/`lwbrx`/`sthbrx`/`stwbrx` for their
  elements. Getting this wrong hung Speedometer for over an hour.

Test with `jsc`, forcing everything through the JIT
(`--thresholdForJITAfterWarmUp=1 --thresholdForJITSoon=1`) and comparing
against `--useJIT=false`.

### What it bought

On jsc micro-benchmarks the JIT is **1.5 to 3.5 times faster** than the
interpreter (integer loops 3.5x, property access 3x, calls 3x).

On Speedometer 3.1 on the PowerBook G4, the score moved 0.259 (C loop) ->
0.261 (native interpreter) -> **0.271** (JIT), against PowerFox 26.4's 0.189.
The JavaScript-heavy suites gained 15-29% (Charts-observable-plot, Perf
Dashboard, Stockcharts, TipTap), but Speedometer mostly measures **style,
layout and painting**, where the JIT changes nothing.

### Where the remaining time goes (profiles on the G4)

| Suite | Main-thread time |
|---|---|
| TodoMVC-JavaScript-ES5 | layout 70%, of which AppKit repaint invalidation 18%; JavaScript ~0% |
| The Complex-DOM suites | style and layout over the whole big DOM; per-layout walks of every RenderLayer |
| Charts-chartjs | about 60% Core Graphics rasterizing antialiased paths, 29% JavaScript |

Three fixes came out of those profiles (commit "WebCore: cheaper repaints,
selection gaps and custom properties"): repaints handed to AppKit once per run
loop pass (**+10% on ES5**), selection changes no longer walking every layer,
and custom property resolution touching only the properties an element sets
(this one speeds up loading such pages, not the measured part).

### To beat PowerFox on every suite

Still losing six of twenty. In order of how much they need:

1. **Charts-chartjs** (needs 51%): Core Graphics path rasterization. Would need
   canvas-level work, e.g. drawing axis-aligned hairlines as rectangles, and a
   faster path for Chart.js's `Object.assign` loops.
2. **ES6-Webpack-Complex-DOM** (30%), **Svelte** (25%), **ES5** (11%),
   **Preact** (15%), **Angular** (8%).

The Complex-DOM losses share one cause: a small DOM change relayouts the whole
page, and every layout walks every RenderLayer (`updateLayerPosition`,
geometry maps, repaint rectangles). Gecko reflows only dirty subtrees. The
fixes worth trying, in order: relayout boundaries so the TodoMVC app doesn't
drag the big DOM into its layout; layer position updates only for layers whose
renderers moved; and cheaper repaint rectangle computation.


## 19 September: layer positions, and eighteen suites out of twenty

The second of the three fixes above turned out to be the big one.

After every layout, `RenderLayer::updateLayerPositions` walked *every* layer in
the page, recomputing each layer's position, its clip rectangles and its
repaint rectangles, pushing and popping a geometry map along the way. On a
TodoMVC page with a few thousand positioned elements that walk cost more than
the layout that prompted it, and nearly all of it recomputed values that had
not changed.

Each renderer now carries the number of the layer position update its subtree
last needed: four bits, in `RenderElement`, which had spare room in a bitfield
word (`RenderObject` has none — it is guarded by a static assertion on its
size). A renderer that was laid out marks itself and its ancestors with the
view's current generation, and so do a layer that scrolled, one whose visible
content changed, and one that needs a full repaint. The view advances the
generation after each update, so the marks expire by themselves and nothing
has to be cleared. `updateLayerPositions` then skips any child whose subtree
carries an older generation — unless something above it moved, in which case
its positions really have changed.

| Suite | PowerFox | Before | After |
|---|---|---|---|
| TodoMVC-Svelte-Complex-DOM | 2698 | 3532 | **1277** |
| TodoMVC-Preact-Complex-DOM | 2995 | 3668 | **1427** |
| TodoMVC-Lit-Complex-DOM | 9758 | 4728 | **2223** |
| TodoMVC-React-Complex-DOM | 7380 | 6276 | **3895** |
| TodoMVC-Angular-Complex-DOM | 6022 | 6557 | **4250** |
| TodoMVC-JavaScript-ES6-Webpack | 5864 | 8687 | **5633** |
| TodoMVC-jQuery | 34840 | 11191 | **10237** |

Speedometer 3.1 overall: 0.271 -> **0.345**, against PowerFox's 0.189.
Eighteen of the twenty suites are now faster than PowerFox.

Skipping paint work is exactly the kind of change that renders stale pixels, so
it is checked against a page (`layertest.html`) that reaches its final state by
mutating the DOM the way a TodoMVC app does, compared against the same page
built in one go. The comparison uses the window's real contents through
`CGWindowListCreateImage` rather than a fresh re-render, so anything left
unpainted would show: the two are identical pixel for pixel, at the top of the
page and scrolled.

### What is left

Two suites:

1. **Charts-chartjs** (needs 50%): still Core Graphics rasterization, 60% of
   its time. Canvas-level work, as before.
2. **TodoMVC-JavaScript-ES5** (needs 9%): the remaining layout cost on a page
   whose every change relayouts the list. Relayout boundaries are the fix.

## 20 September: what the ES5 suite actually costs

The plan said the next thing for TodoMVC-JavaScript-ES5 was WebKit's HTML
fast-path parser, which Apple measured at about 20% on this very suite. A
fresh profile says otherwise: **HTML parsing is 2.4% of the main thread
here**. Apple's 20% was against their own baseline, on hardware where the
rest is far cheaper; our engine's costs sit elsewhere. That saved a week or
two of work on the wrong thing, and is the argument for profiling the machine
in front of you rather than reading someone else's numbers.

Where the time went instead (4176 main-thread samples, after patches 0053 to
0056):

| | |
|---|---|
| layout | 34.8% |
| unclassified | 31.4% |
| style | 10.3% |
| DOM | 7.1% |
| JS runtime | 6.4% |
| parse/load | **2.4%** |

The unclassified third is where the interesting costs turned out to be, and
almost none of them are layout algorithms:

- `restGPRx` 2.9% - GCC's out-of-line register restore helper, reached through
  a **branch island** because WebCore is too big to reach it directly. No GCC
  6.5 option turns this off on darwin-ppc; `-mno-multiple`, `-fno-shrink-wrap`
  and `-O2` all still emit the call.
- `pthread_getspecific` 2.2%, mostly under `fastMalloc` and `fastFree`:
  bmalloc's per-thread cache. bmalloc has a fast path for this
  (`_pthread_getspecific_direct`) but it needs `<System/pthread_machdep.h>`,
  which Leopard does not have - it arrives in Snow Leopard. No cheap fix.
- `floorf`, `round`, `lroundf` about 2%, all through dyld stubs, called from
  text measurement and repaint rectangles. The G4 has no `frim`, so GCC cannot
  inline them.
- `objc_msgSend_stret` 1.5%, under `-[NSScrollView documentVisibleRect]`.

### What came of it

**The visible content rectangle is now held for the length of a layout or a
paint** (patch 0057). Neither can move the view while it runs, and layout
asks hundreds of times - every repaint rectangle wants it - at the cost of an
Objective-C call returning a structure plus a `floorf` and a `ceilf`. ES5
went from about 5332 to a mean of 5152 ms.

**Inlining `computedCSSPadding` made things worse, and was reverted.** It is
the hottest single WebCore symbol in the profile (2.3%), a cross-translation
-unit call wrapping what is usually `return length.value()`, so moving it into
the header looked free. Six runs said 5286 ms against 5126 for the same build
without it - about 3% slower. On a 32KB instruction cache, inlining a small
function into several hundred call sites in a 30MB library costs more than the
call it saves. Worth remembering before the next "obviously free" inline.

Measurement discipline this needed: a single run of this suite varies by 3%,
and two batches of the same build differed by 1.2%. Nothing under about 2% is
a result without several runs on both sides.

### Where ES5 stands

About 5152 ms against PowerFox's 4846: 6.3% behind, from 9-10%.

## 20 September: the font panel

Speedometer 3.1: **0.342 -> 0.494**, and **nineteen of twenty suites** are now
faster than PowerFox. The change is five lines, and finding it took a profile
read the right way round.

The earlier profile of TodoMVC-JavaScript-ES5 was bucketed by *self* time:
layout 34.8%, style 10.3%, parsing 2.4%. Every conclusion drawn from it was
wrong, because the question it answers is "what code is running" rather than
"who asked for it". Read *inclusively*, 2835 of the 4176 main-thread samples
sit under one call:

    -[WebHTMLView _selectionChanged] -> _updateFontPanel
      -> Editor::fontForSelection -> styleForSelectionStart
      -> VisiblePosition::canonicalPosition
      -> Document::updateLayoutIgnorePendingStylesheets    (2817 samples)

That function exists to tell the shared NSFontManager what font the selection
is in, so an open Font panel shows the right thing. Finding out lays out the
whole document, synchronously. TodoMVC assigns to `input.value` about two
hundred times against a list of up to a hundred items, so the page was laid
out two hundred times where once would do - O(N^2) layout, and 68% of the test.

Nothing reads the shared font manager unless a Font panel exists, and this
browser has no Format menu. Skipping the work when
`+[NSFontPanel sharedFontPanelExists]` is false costs nothing and gave:

| Suite | Before | After |
|---|---|---|
| TodoMVC-Svelte-Complex-DOM | 1272 | **428** |
| TodoMVC-Preact-Complex-DOM | 1432 | **570** |
| TodoMVC-WebComponents | 2091 | **995** |
| TodoMVC-JavaScript-ES5 | 5332 | **1947** |
| TodoMVC-JavaScript-ES6-Webpack | 5616 | **2238** |
| TodoMVC-jQuery | 10222 | **6613** |
| TodoMVC-Angular-Complex-DOM | 4197 | **2974** |

The suites that never type into a text field - the news sites, the charts,
Stockcharts, Perf-Dashboard - did not move, which is how you know the
explanation is the right one.

### What this invalidated

Three pieces of planned work, all of them well argued from the old profile:

- **The HTML fast-path parser.** Parsing was 2.4% of a test that was 68%
  waste. Apple's ~20% for this suite was against their own baseline.
- **Style rule collection and text measurement.** 100% and 99% of their
  samples were inside the wasted layouts.
- **`computedCSSPadding`**, the hottest single symbol: 89 of its 100 samples
  were inside the waste. Inlining it had already measured 3% slower.

The lesson is cheap to state and was expensive to learn: a self-time profile
tells you what is running, and the thing to ask of any hot symbol is not "how
do I make this faster" but "who called it, and did they need to?". A counter
on `Document::updateLayout()`, printed per test step, would have found this in
minutes; it is worth having permanently.

## 20 September: a register nobody was using

GCC's PowerPC/Darwin backend decides whether to save r31 by asking one
question - is -fPIC on? - and on Darwin the answer is always yes, because
-fPIC is the default. The prologue, meanwhile, only *sets up* r31 when the
function needs a picbase. So every function that never touches r31 still
opened with `stw r31,-4(r1)` and closed with `lwz r31,-4(r1)`.

In our WebCore that was 23,167 functions. With the fix it is 7,239. Fifteen
thousand nine hundred functions lost two instructions, a stack store and a
stack load, and the binary lost 87KB.

It is GCC PR target/88343 - Iain Sandoe's own Darwin bug, fixed for 7.5 and
8.3 in 2019, with a note on the bug saying 6.x would need someone maintaining
a branch to apply it. Nobody was. `scripts/toolchain/gcc-pr88343-darwin-picbase.patch`
carries the 7.5 form of the fix, which is the one to take: the first attempt
was reverted on both branches for under-saving r30 on 32-bit soft-float Linux.
That failure was entirely on the ABI_V4 side and cannot reach a Darwin-only
cross compiler, but the settled form is the settled form.

Three checks before trusting a patched compiler with the whole engine: a leaf
function compiles to `blr` alone; a function that touches a static still saves
and restores r31 around its picbase; and the twelve checks in
`engine/tests/features-modern.html` pass on a full rebuild.

## 20 September: two instruments, and what they found

A Speedometer run costs the better part of an hour, which makes it a poor way
to answer a specific question. Two pages in `engine/tests/` answer specific
questions in seconds.

`canvas-paths.html` draws a Chart.js-shaped chart in a loop: grid lines, a
filled area, a polyline, a small filled-and-stroked circle at every point,
axis labels. It reports milliseconds per chart. The first thing it said:

| | ms per chart |
|---|---|
| Captain Polliwog | **48.2** |
| PowerFox | 99.1 |

We are twice as fast as PowerFox at drawing exactly what Chart.js draws. So
the one suite we lose - Charts-chartjs, 3011 against 1575 - is not lost in the
rasteriser, and the planned sprite-stamp cache for CoreGraphics would have
been a great deal of work aimed at the wrong half of the test. A profile of
that suite agrees: about a third of the main thread is under the canvas
`fill()` and `stroke()` entry points, which leaves two thirds somewhere else.

`js-kernels.html` is the instrument for the other two thirds: eight small
kernels in the shapes a charting library actually writes - monomorphic
property access, a call site seeing four shapes, option-bag literals, numeric
arrays, closures, string building, scale arithmetic, and array methods taking
a function. PowerFox runs IonMonkey; we run JavaScriptCore's baseline JIT,
which compiles each bytecode once with no type feedback. The ratio per kernel
should say which parts of that difference are worth attacking one at a time,
rather than leaving "write an optimising tier" as the only answer.

## 20 September: five and a half thousand stubs to our own code

WebCore's `__picsymbolstub1` section is 242KB - 7,564 stubs of eight
instructions each, every one ending in a `bctr` the processor cannot predict.
But WebCore has only 2,777 undefined symbols. **5,484 of those stubs point at
symbols WebCore itself defines.**

They are there because the build exports everything: 73,627 symbols, against
the few thousand Apple's own WebCore exports. Apple's Xcode build sets
`GCC_SYMBOLS_PRIVATE_EXTERN` and lists what to export in a `.exp` file; the
CMake Mac port we build from has neither, so every template instantiation and
every out-of-line inline is a coalesced, interposable, exported symbol - and a
call to one of those has to go through a stub, because dyld is entitled to
choose a different definition.

The sampled cost is real: 6.8% of the main thread in TodoMVC-JavaScript-ES5,
and 4.1% in Charts-chartjs, is spent *inside* stub code, before counting the
mispredicted branch at the end of each one.

The fix is already written into the source. `WEBCORE_EXPORT`, `WTF_EXPORT_PRIVATE`
and `JS_EXPORT_PRIVATE` expand to `visibility("default")` on Cocoa, and they
annotate exactly what crosses a framework boundary; the GTK port builds this
way. All that is missing is `-fvisibility=hidden`, which
`scripts/toolchain/webkit.sh` now takes through `EXTRA_FLAGS`.

## 22 September: YouTube's 50MB function, and the syntax gap is nearly closed

**A crash, not slow loading.** YouTube showed grey placeholders on the iBook
and the app quietly quit. The crash reports (four of them, from ordinary
use) all end in the same place: `JIT::compileWithoutLinking`, linking a
branch. YouTube's main script contains one function of **2.5 million
bytecode words**, whose baseline code came to about 50MB. A PowerPC branch
reaches 32MB; the range check is a `RELEASE_ASSERT`, so the browser stopped.
The baseline JIT now gives up on a function once its main pass passes 12MB,
leaving room for the slow paths, and reports failure the way a failed
allocation does, so the interpreter keeps running that one function and
everything else stays compiled (patch 0062). YouTube then loads on the
iBook with its thumbnails, 157 resources, no crash.

**The JavaScript syntax gap is nearly closed.** A survey of 20 sites with
the bundled engine and debug logging found **two** parse failures in all:
Amazon (`Can't create duplicate variable: 'UIStrings'`) and x.com
(`Unexpected identifier 'r'` after a declaration, which is what an
unsupported `using` declaration looks like). Everything else - YouTube,
Reddit, GitHub, Wikipedia, the New York Times, the BBC, CNN, The Verge,
Apple, Stack Overflow, eBay, Instagram, Twitch, ESPN, DuckDuckGo - parses.
The earlier "SyntaxError" logs that suggested otherwise came from a process
running *Tiger's* 2009 WebKit, before the engine-loading fix.

**Status feed.** View > Show Page Activity (off by default) puts what the
page is doing in the status bar: what is being contacted, how many of its
pieces have arrived, which site it is still fetching from after the page
looks finished, and how long the page's own scripts held the browser up.
The last is measured by a timer that ticks four times a second on the main
thread: when a tick arrives late, that is how long the page ran without
letting go.

## 22 September: preparing for a current WebKit

Decision: the modern-engine target is **WebKitGTK 2.52.6**, not the 2024
branch. Checked in its own source rather than taken on trust:
`PlatformCPU.h` still defines `CPU(PPC)` for 32-bit big-endian, and
`OptionsGTK.cmake` switches Skia on **only** for little-endian machines and
keeps Cairo for the rest - upstream still builds for machines like ours.

What is in place on the MacBook Pro's VM, beside the GCC 6.5 toolchain the
604 engine keeps using (`/opt/ppc`, untouched):

- **GCC 14.2** cross compiler for `powerpc-apple-darwin9` in
  `/opt/ppc-modern` (`scripts/toolchain/build-modern-toolchain.sh`), sharing
  the old toolchain's cctools and ld64, defaulting to the G3 with a 10.4
  deployment target as before. It compiles and links C++20 (concepts,
  `std::span`) for a G3 on Tiger. Two things it needed:
  - libgcc links itself with `-arch` whatever `lipo` reports, which for a
    G3 build is `ppc750`, a name GCC 14's driver rejects
    (`gcc14-darwin-ppc750-arch.patch`).
  - **libatomic is required.** 32-bit PowerPC has no 64-bit atomic
    instruction and WebKit uses 64-bit atomics throughout; its configure
    stops with "Failed to detect support for atomic variables" without it.
    It is built shared, like the rest of the runtime: one lock table for
    every image, or two images could lock the same address apart.
- **CMake 3.31** (2.52 needs 3.20; Ubuntu 20.04 has 3.16) and **ICU 74.2**
  for PowerPC (2.52 needs 70.1), with the same hand-written data object the
  604 toolchain needs, since ICU's `genccode` writes words in the build
  machine's byte order (`scripts/toolchain/build-modern-deps.sh`).
- `scripts/toolchain/webkit-modern.sh`, which configures and builds 2.52
  from the released tarball, and `ppc-darwin-modern.cmake`.

**Milestone 1 is the JSCOnly port**: JavaScriptCore alone, which needs
nothing but ICU, in the C interpreter. It answers whether 2.52 compiles with
GCC 14 for Darwin, whether 32-bit big-endian still works, and how slow the
interpreter is on a G4 - before anything larger is attempted.

**The shape of the full port is still open.** Both the GTK and WPE ports of
2.44 and later require EGL, which Leopard has no implementation of, and GTK
itself. The alternative is the HaikuWebKit model already recommended above:
carry WebKitLegacy out of tree with our own networking (which Captain
Polliwog already owns) and a native graphics context. That decision comes
after milestone 1.

**Disk is the practical constraint.** The MacBook Pro has about 17GB free,
and the VM's disk image only grows; a full WebKit build tree is 20-30GB.
Milestone 1 fits. The full engine will need space freed, an external disk,
or the Mac Studio.

## 23 September: the optimizing compiler on a G4

JavaScriptCore has three tiers. This browser has had two of them: the
interpreter and the baseline JIT that Leopard WebKit's PowerPC port
provides. The third, the DFG, was switched off in `Platform.h` for PowerPC
and had, as far as any record shows, never been built for a big-endian
32-bit machine. It is the largest single lever left in the engine, so it
was worth finding out what it does here.

It builds. Turning it on is `DFG=ON scripts/toolchain/webkit.sh configure
leopard-g4-jit`; the CMake option is what matters, because WebKit generates
a config header from it that overrides anything passed as a compiler flag.
It compiles a hundred and forty-one more object files, and the code it
produces for a hot function is smaller than the baseline's - 960 bytes
against 2496 for the same loop.

Where it works, it is worth a great deal. Measured on the PowerBook G4
against the same build with the tier switched off, both runs back to back
under the same load:

    bit operations   1630ms -> 238ms    6.9x
    array sort        479   -> 226      2.1x
    floating point   1542   -> 1026     1.5x
    integer loop     2889   -> 2325     1.24x
    recursion          31   ->   29
    string building   290   -> 456      0.6x - slower
    JSON             407   -> 430       about the same

It is also not correct yet. Three things were wrong and two are fixed:

The DFG stopped in its own bytecode parser on the first function it tried
to compile. Each node stores its operand in a union of a 64-bit field with
a pointer, writes the 64-bit member and reads the pointer; on a
little-endian machine those are the same word, and on this one the pointer
read returns the zero above it (patch 0067).

Every result the DFG takes back from a C function had its two halves the
wrong way round. A 64-bit value comes back in a register pair, high word
first, and the high word of a JSValue here is its tag. The baseline JIT
says so at each of its own call sites, having been ported by hand; the DFG
has one place where all of its calls arrive and nobody had been there
(patch 0068). This does not crash. A string comes back as a denormal
number around 1e-275 - a heap pointer read as a double - and an integer as
a value whose tag is its own contents.

What remains is in the same family and has not been found yet. Reading a
global inside compiled code can return a wrong value, and entering
compiled code from a loop already running makes it much more likely:
`--useOSREntryToDFG=false` takes one test from 77 wrong answers to none.
Arithmetic itself is clean - every operator over every interesting operand
pair, including the overflow boundaries, matches the interpreter exactly.

So the tier stays off by default, which is what `DFG=OFF` in `webkit.sh`
means. What it needs is the rest of the work the baseline JIT already had:
someone going through the paths that move a JSValue between registers,
the stack and C, and saying which half is which. The gain measured above
is what that would buy.

`scripts/jit/dfg-differential.js` is how the wrong answers were found. It
runs the same work through the engine twice, once with the tier on and
once with it off, and folds every answer into one number per case, so a
value that goes wrong on the two hundredth iteration of one case shows up
as a single changed line. It needs no special build - any `jsc` will run
it, and it is the first thing to run after touching anything in this area.

One thing that looked like a bug is not one. Integer typed arrays on this
engine are little-endian: the bytes under `new Uint32Array([0x01020304])`
read back as 4,3,2,1, while a `Float64Array` is native. That is upstream
WebKit's deliberate choice for big-endian machines, because web content
assumes it, and patch 0052 is what makes the JIT's own fast paths agree
with the runtime. It is not something to fix.

## 23 September: what a newer compiler is worth

The engine is built by GCC 6.5, because that is what Leopard WebKit's
PowerPC port was written against. The 2.52 port needed a newer one and has
GCC 14.2 at `/opt/ppc-modern`, which knows the 7450 far better than 2015's
compiler did, so it is worth asking what the same source does through it.
`TOOLCHAIN=modern` on `webkit.sh` selects it, into a build directory of its
own so the two can be compared without rebuilding either.

JavaScriptCore builds with three added includes and nothing else (patch
0069): GCC 14's headers no longer pull in stdio, `<iterator>` or
`<functional>` by accident.

Measured on the PowerBook, same source, same JIT, both runs back to back:

    JSON             422ms -> 384ms   9%
    bit operations  1614   -> 1525    5.5%
    array sort       480   ->  459    4.4%
    string building  292   ->  283    3.3%
    object churn    1421   -> 1383    2.7%
    integer loop    2883   -> 2810    2.5%
    floating point  1465   -> 1436    2%
    recursion         30   ->   30

Between two and nine per cent, for nothing but a newer compiler. It is
modest here because these are JIT-bound: the compiler only gets to improve
the runtime, the interpreter and the collector, while the JIT writes its
own code either way. The part of the engine where a compiler has the most
to say is WebCore, which is what Speedometer actually spends its time in,
so the number to care about is not this one.

One thing had to be solved to get there. Thread-local storage is emulated
on 10.5, and the state lives in whichever copy of the runtime an image
links. GCC 6's shared libgcc exports the two functions that reach it, so
the engine's three frameworks share one copy. GCC 14 hides them, and each
framework would take its own from the unwinder archive - at which point
`std::call_once` writes its callable through one copy, libstdc++ reads it
through another, finds null, and the engine jumps to zero before it has
done anything at all. It is the first thing that happens on startup, so
this is not subtle to find; it is only subtle to explain.

`build-modern-emutls.sh` is the answer. It builds those two functions, and
nothing else, as a library every image shares, and relinks libstdc++ from
its static archive to import them rather than carry its own - which needs
the object that defines them removed from the unwinder archive first, or
the linker puts the copy straight back. After that the engine starts.
`PPC_STATIC_RUNTIME=1` remains for giving each image its own runtime,
which is what the measurement above was taken with.

## 23 September: why 0.3.2 disappeared on a G3

Reported as "it crashes on YouTube and MacRumors". Eighteen entries in the
crash log on the Pismo, and not one of them was a crash: every one was dyld
refusing to bind a symbol. Three separate faults, and the first two are the
same fault wearing different hats.

The lazy binding is what makes this hard to see. A reference dyld cannot
satisfy does not stop the application starting - it is resolved the first
time the code that needs it runs. So the browser launches, renders, browses,
and then vanishes on the page that happens to reach it. From the outside that
is a browser that crashes on YouTube, and it sends you to look at YouTube.

**The conformance variants.** The 10.5 SDK renames `open`, `close`, `mmap`,
`mktime` and a dozen others to `$UNIX2003` symbols, and decides whether to by
reading `__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__` - which Apple's
compiler defines from `-mmacosx-version-min` and FSF's does not. So every
library cross-built here asked for seven functions 10.4 never had. ICU wanted
`mktime$UNIX2003`, which is a page with a date on it.

Saying `-mmacosx-version-min=10.4` is not enough, and neither is
`_NONSTD_SOURCE`: a project that defines `_POSIX_C_SOURCE` or `_XOPEN_SOURCE`
- ICU and libxslt both do - takes an earlier branch in `cdefs.h` that turns
conformance on regardless, and combining the two is an error. The flag that
works is `-D__DARWIN_UNIX03=0`, which is what the header itself ends up
testing. Every dependency is built with it now.

**zlib.** libxml2 was configured `--with-zlib` for a feature a browser never
uses: reading a `.gz` straight off disk. Against the 10.5 SDK that recorded a
call to `gzdirect()`, which Leopard's zlib has and Tiger's has not. Built
`--without-zlib` now.

**The unwinder.** GCC built libstdc++ naming the system's libgcc_s as well as
its own, and the unwinder functions it imports are hinted at the system one.
Leopard's has `_Unwind_GetIPInfo`; Tiger's has not. So the first C++
exception the engine threw would have ended it. package-webkit.sh now points
that reference at the libgcc_s in the bundle, which is the one everything
else already uses.

With those three fixed the application binds every symbol it has at launch -
`DYLD_BIND_AT_LAUNCH=1` is the way to ask, and is worth running on any build
before it goes near a Tiger machine. MacRumors then loaded 44 of its 49
pieces before dying of something else entirely.

**The something else: QuickTime.** WebCore looks up QTKit's constants by name
at runtime, and a required lookup that misses is a deliberate abort. Mac OS X
10.4 ships QTKit 7.0.4, and six of the names WebCore asks for arrived later -
the aperture modes in 7.2, the cross-site security policy and the video
renderer's own notification later still. So on 10.4 the browser did not fail
to play a video. It stopped, on the first page holding one, which on the
modern web is most of them. Those six are looked up the optional way now and
each use asks first (patch 0070). Clean aperture is the only loss: a movie
plays at its encoded size rather than its display size.

To stop this class of thing shipping again, `engine/tiger-baseline-symbols.txt`
records what 10.4.11 actually exports for the three libraries where a build
against the 10.5 SDK can ask for something absent, and package-webkit.sh
refuses to package a Tiger build that wants anything outside it.
`scripts/tiger-symbol-check.sh` does the same against an installed copy,
though on the machine itself Tiger's own `nm` cannot read binaries this
toolchain produces - it reports "unknown load command" and then says nothing
is wrong, which is worse than refusing - so dyld remains the honest test.

## 23 September: the smear where a heading should be

Reported as "everything, especially text, is on top of each other" on a
G3, with apple.com's hero section unreadable. It was, and the way it was
wrong is worth writing down, because two plausible explanations were wrong
before the right one turned up.

The screenshot said more than the report did: Apple's navigation bar -
Store, Mac, iPad, iPhone, Watch - was perfect, directly above a headline
that was a single unreadable blob. So it was not text in general. The
first guess was web fonts, since apple.com and YouTube use them and
example.com, which had always rendered, does not. A test page with the
same sentence in Helvetica and in a downloaded font killed that: both
collapsed.

What settled it was measuring rather than looking. The browser can run a
script on a page and report the answer (`scripts/debug-probe.sh`), so it
was asked for the width of one line of text in eleven fonts, twice each -
once as the page would get it, and once with `text-rendering:
optimizeLegibility`, which is the one property that makes WebKit measure
through CoreText instead of CoreGraphics:

    Lucida Grande  plain=260  legibility=260
    Helvetica      plain=22   legibility=234
    Times          plain=20   legibility=214
    Courier        plain=26   legibility=277
    Verdana        plain=25   legibility=267

Twenty-two pixels for twenty-one characters. Asked again at four sizes,
the plain answer was 22 at 11px, at 22px, at 44px and at 88px, while
CoreText said 117, 234, 467 and 934. CoreGraphics on 10.4 ignores the
text matrix it is handed for glyph advances and answers in em units, so
every glyph is drawn about one unit from the last: the line piles up in
the space of a single character.

Lucida Grande is the exception, which is why the system font and only the
system font looked right, and why the navigation bar sat crisply above
the smear.

The first fix was wrong in a way worth remembering. It fell back to
CoreText when the advance came back as zero - but it does not come back
as zero, it comes back as one per glyph, so the fallback never ran and
the rebuilt engine behaved exactly as before. A screenshot would have
been read as "still broken, try something else"; the numbers said "your
condition never fired". Tiger now measures every glyph through CoreText,
under the `CP_TIGER` build flag, which marks the places where 10.4 needs
different code rather than a missing function filled in (patch 0072).
WebKit caches advances per glyph, so it costs one call per glyph per font.

Three bugs today were this same species: 10.4's CoreText taking `double`
where Leopard takes `float`, the QuickTime constants that abort when
absent, and this. None of them are missing symbols, so no symbol
inventory finds them - they are the same calls behaving differently. The
probe is the tool that finds them, and it is worth running against a new
Tiger build rather than trusting a page that looks about right.

## 23 September: the GCC 14 engine builds, and does not start

WebKit 604 compiles end to end with GCC 14.2 now (patch 0073). What it
took, for anyone doing this again: seven headers it no longer supplies by
accident, three linker options it forwards differently, two inline
definitions it declines to emit, four availability collisions where the
10.5 SDK marks a 10.6 function unavailable rather than absent, and one
internal compiler error.

It also does not run. The first WebView it makes takes the application
down:

    0  libobjc  _class_isInitialized + 0
    1  libobjc  _class_lookupMethodAndLoadCache + 84
    2  libobjc  objc_msgSendSuper + 188
    3  AppKit   -[NSScrollView tile] + 148
    4  WebKit   -[WebDynamicScrollBarsView(WebInternal) tile] + 60

A null class reaching objc_msgSendSuper: `[super tile]` in a category,
with the superclass pointer never fixed up. Three things that would
explain it have been checked and are not it. Both builds emit the same
__OBJC segment, so it is not the fragile-versus-modern runtime ABI. Both
carry an identical __image_info, so the runtime is not refusing the image.
And the same harness runs the GCC 6 engine on the same machine, so it is
not the test.

All three of those have since been ruled out too, by reading the
binaries rather than by argument.

The fault address says what kind of failure this is. In the fragile
`struct objc_class` the fields run isa(0), super_class(4), name(8),
version(0xc), info(0x10), and `_class_isInitialized` reads `info`. A
protection fault at 0x10 is therefore a *null* class, not a corrupted
one - a link that was never fixed up. An unresolved fragile-ABI
super_class would still hold the address of the string "NSView" and
would fault somewhere wild instead.

-fvisibility=hidden is not it. Both builds are given it - confirmed in
the CMake caches - and in the GCC 14 build it is demonstrably in effect:
WebCore carries 71,383 private-external symbols. Yet of the 150
`.objc_class_name_*` symbols in that binary, the number marked private
external is zero, exactly as in GCC 6 (46 defined external, 104
undefined external, in both). Neither compiler lets visibility reach an
Objective-C class symbol. WebKitLegacy is exempt anyway, by patch 0060.

The section renaming is not it, twice over. All four -rename_section
options name __TEXT explicitly, and the fragile ABI's metadata lives
entirely in __OBJC; and the flags are identical in the build that works.

Two libstdc++ is not it either: nothing in libstdc++ takes part in class
registration, which happens when dyld binds the image, before any C++
static initializer runs. The split-runtime failure this port already
knows has a different signature - emulated TLS state splitting, failing
inside pthread_once, long before a WebView exists.

The metadata itself is sound. Class, metaclass, category, protocol,
module_info, symtab, cls_refs and message_refs records were compared
entry by entry across both frameworks: identical, and in the same order.
The three WebCoreView categories on NSView, NSClipView and NSScrollView
emit their class field as a __cstring name pointer in both, which is the
correct pre-fixup form, and the super-send in each loads from the same
__cls_refs slot, holding the same name, in both.

What is left is not Objective-C at all. The GCC 14 image orders its
LC_LOAD_DYLIB commands differently: libSystem.B.dylib, which contains
libobjc on 10.5, comes 14th, ahead of CoreFoundation and Cocoa, where
GCC 6 puts CoreFoundation 4th, Cocoa 12th and libSystem last. That
changes the order in which images are bound and their classes
registered, and a class reference bound while its defining image is not
yet registered resolves to null - which is the fault above. Against it:
the application itself links -framework Cocoa before -framework WebKit,
which ought to force AppKit first whatever WebKitLegacy asks for. So
this is a suspect, not an answer, and the next step is a measurement and
not another argument: DYLD_PRINT_LIBRARIES on both engines to get the
real bind order, and DYLD_INSERT_LIBRARIES pointing at Cocoa to force
AppKit ahead of everything. Neither needs a rebuild.

Two smaller differences are worth keeping in view: GCC 14 adds a
libemutls.1.dylib dependency and weakens ___emutls_get_address to a weak
undefined symbol, which resolves to null rather than failing; and the
GCC 6 build was configured with -mcpu=750 -mtune=750 appended through
EXTRA_FLAGS, so the comparison between these two trees is not one
compiler against another on the same target. That wants fixing before
any A/B is trusted.

So the measurement this was all for - what a modern compiler is worth on
WebCore, where Speedometer actually spends its time - is still not taken.
The JavaScript-only figure stands at two to nine per cent, and that
understates it.

For the record, the same site survey on the GCC 6 engine, on the
PowerBook G4:

    en.wikipedia.org/wiki/PowerPC    7.3s   117MB
    apple.com                       31.3s   180MB
    cnn.com                     no load    285MB   3 script errors

## 23 September: the optimizing tier is correct on one machine and not the other

The remaining DFG fault has a reduced case now
(`scripts/jit/dfg-array-length.js`): every array's length reads back as
2.121995789e-314, a JSValue whose halves read as 1 and 0 taken for a
double, while the elements of the same array read back perfectly. `length
| 0` answers 0, so the register holds nothing useful before anything boxes
it - this is not the boxing.

Where it happens is the interesting part. On the **G3 running Tiger** the
whole differential suite passes: twenty cases, no differences, with the
tier on. On the **G4 running Leopard** every length is wrong. Ruled out by
building and testing rather than by reading:

- not a stale binary - rebuilt from the same source, same fault
- not AltiVec - `-mno-altivec`, same fault
- not the processor tuning - `-mcpu=750 -mtune=750` on the Leopard
  variant, same fault
- not the build at all - the Tiger build shows the fault when run on the
  G4

That last test is worth a warning: the Tiger build links libTigerShim,
which deliberately answers CoreText and CoreAnimation the way 10.4 shapes
them, and on 10.5 that is wrong. The objc runtime says so on startup, in
half a dozen lines about classes implemented twice. So the result is
suggestive and not clean, and the conclusion drawn from it here - that the
processor rather than the build decides - is not yet proven.

Processor and system cannot be separated with the machines here: there is
a G3 on Tiger and a G4 on Leopard, and no G4 on Tiger or G3 on Leopard.
The Tiger guest under PowerEmu is Tiger on a G4-class processor, which is
exactly the missing corner, and would settle it in one run.

What this does mean today: on Tiger and a G3 the tier is correct, and
worth 3.5x on recursion and 1.5x on object churn there, against
regressions on bit operations and strings that look like compile time
costing more than the compiled code saves on a 500MHz machine. On the G4,
where the tier was worth 6.9x on bit operations, it still computes wrong
answers and stays off.

## 24 September: Speedometer 3.1 on the PowerBook G4, four runs

The score varies enough between runs that one number would have been
misleading. Four runs, each with caches cleared and nothing else running,
about 1440MB free at the start of each:

    0.474   0.411   0.450   0.437      median 0.444

The spread is the engine's, not the harness's. Within a suite the slow
iterations spike in all three sub-metrics at once - iteration 5 of
TodoMVC-JavaScript-ES5 ran 2316ms against a 1023ms minimum, and its async
and third metrics spiked by the same proportion in the same iteration.
Three independent measurements moving together is a global pause, which
on this engine means a full collection. The geomean absorbs them: run 4
reported 2317.13 +- 206.36ms (8.9%) while its individual suites ranged
from 9.6% to 28.3%.

All twenty suites, from run 4, in milliseconds:

| Suite | ms | Suite | ms |
|---|---|---|---|
| TodoMVC-Svelte-Complex-DOM | 523 | TodoMVC-Backbone | 2115 |
| TodoMVC-Preact-Complex-DOM | 644 | Charts-observable-plot | 2129 |
| Editor-CodeMirror | 814 | TodoMVC-JavaScript-ES5 | 2560 |
| TodoMVC-WebComponents | 1104 | Editor-TipTap | 2631 |
| TodoMVC-Vue | 1469 | TodoMVC-ES6-Webpack-Complex-DOM | 2875 |
| TodoMVC-Lit-Complex-DOM | 1746 | TodoMVC-React-Complex-DOM | 3231 |
| Perf-Dashboard | 3380 | TodoMVC-Angular-Complex-DOM | 3344 |
| Charts-chartjs | 3602 | TodoMVC-React-Redux | 3716 |
| React-Stockcharts-SVG | 4389 | NewsSite-Next | 5432 |
| NewsSite-Nuxt | 6030 | TodoMVC-jQuery | 7195 |

Charts-chartjs is 3602ms, which is mid-pack among our own suites. That
was briefly read here as the Core Graphics work having landed, which it
does not show: being mid-pack against our other suites says nothing
about PowerFox. With PowerFox's own figures now in hand it is still the
one suite we lose - see below.

One measurement note for anyone repeating this. The debug script only
runs when CPDebugSnapshotPath is set: the evaluation lives inside
-writeDebugSnapshot, and that is only scheduled when the path is
non-nil. Deleting the key disables the probe silently. And the score
element stays empty for the whole run rather than showing a provisional
value, while the hash never advances past #running, so completion has to
be detected from the score appearing and not from the URL.

The comparison against PowerFox is being re-taken. The earlier 0.198 was
measured against a local copy of Speedometer served over the LAN, while
these four ran against browserbench.org, and a number that is going to be
published should not have that difference buried in it.

## 24 September: 2.52's JavaScriptCore runs on PowerPC Mac OS X

Milestone 1 of the modern-engine spike is answered. WebKitGTK 2.52.6's
JSCOnly port, built with GCC 14 for powerpc-apple-darwin9, executes on
Mac OS X 10.4.11:

    $ ./jsc-252 -e 'print(1+1)'
    2

The binary is 59MB, cputype 18 / cpusubtype 9 (ppc750, so it runs on a G3
as well as a G4), and links only libSystem and libedit. ENABLE_STATIC_JSC
puts ICU and the C++ runtime inside it, which is why there is no
libstdc++ in that list and no emulated-TLS problem to solve: one image,
one runtime.

Twenty-six checks, no failures.

Fifteen of them are syntax that WebKit 604 cannot parse: class fields,
private methods, static initialization blocks, Object.groupBy,
Promise.withResolvers, RegExp /d match indices, BigInt, Array.toSorted,
Array.findLast, Object.hasOwn, String.replaceAll, Array.at, optional
chaining, nullish coalescing and logical assignment. The 604 engine has
some of these only because this port backported them by hand.

Eleven are big-endian correctness, which was the real risk: upstream
removed big-endian support on 2026-08-01, so nothing tests these paths
any more. DataView reading and writing in both byte orders, Float64 bit
patterns (0x3FF0... for 1.0, most significant byte first), a Uint8Array
aliasing an Int32Array over one buffer, integer overflow into double,
JSON and Date round trips, Unicode string indexing. All correct. 2.52's
big-endian paths still work, untested upstream or not.

The timings were then taken again on real hardware, and the emulator
turned out to be the slower of the two. On the PowerBook G4 (1.5GHz,
10.5.9) the same set runs in 635ms against the guest's 821ms - fib(24)
in 50ms rather than 70ms. The assumption that QEMU's translation would
outrun a G4 was wrong by about 30% in the other direction. The guest is
a reasonable stand-in for speed as well as correctness, though the real
machine remains the one to quote.

What this does settle is the part that could have stopped the whole
modern-engine plan: 2.52 compiles for this target, runs on it, and is
correct on big-endian. The objc_msgSendSuper crash that blocks the GCC 14
build of the 604 engine does not block this, because JSCOnly has no
Objective-C and creates no WebView.

The guest is also Tiger on a G4-class processor with hw.vectorunit 1,
which is the corner missing from the DFG question. Claiming that data
point needs our own JIT build rather than this JSCOnly one.


### What a JIT-less 2.52 costs, measured

The same five microbenchmarks, on the PowerBook G4, through 2.52's C
interpreter and through the 604 engine's baseline JIT (DFG off), in
milliseconds:

| | 2.52 CLoop | 604 baseline JIT | ratio |
|---|---|---|---|
| fib(24) | 50 | 11 | 4.5x |
| 1e6 integer adds | 133 | 55 | 2.4x |
| 1e5 string concat | 42 | 24 | 1.8x |
| 1e5 object churn | 79 | 26 | 3.0x |
| Array sort 50k | 331 | 314 | 1.05x |
| **total** | **635** | **430** | **1.5x** |

So the honest figure is two numbers, not one. Tight JavaScript loops
cost 2.4x to 4.5x without a JIT, which is what the interpreter is. But
anything dominated by the engine's own native code barely moves - the
50,000-element sort is within 5%, because the comparator is the only
part interpreted. A real page is much closer to the sort than to fib,
which is why the overall figure here is 1.5x rather than 4x.

On correctness the two engines are not comparable at all: on the same
file 2.52 passes 26 of 26 and 604 passes 17 of 26, the nine failures
being syntax from after 2017.

### A one-line reproducer for the DFG fault on the G4

Running that file through the 604 jsc on the PowerBook failed with

    TypeError: a.push is not a function.
      (In 'a.push(...)', 'a.push' is 2.121995789e-314)

2.121995789e-314 is this port's signature for a JSValue whose halves
have been read as a double - the (1, 0) pattern. `--useDFGJIT=false`
makes it go away and all five benchmarks complete; `--useJIT=false`
likewise. So the optimizing tier is corrupting a value on G4/Leopard,
and it takes only a hot loop calling a method on an array to show it:

    var a = []; for (var i = 0; i < 50000; i++) a.push(i);

inside a function called often enough to tier up. Until now this needed
a Speedometer run to provoke. It reproduces in seconds.

The 2x2 that would separate processor from OS is now within reach: the
mini's PowerEmu guest is Tiger on a G4-class processor with AltiVec, and
the missing cell can be filled by running a Tiger JIT build of jsc there
against this same loop.

### A deeper probe, on the PowerBook

The 26-check file was a smoke test. A second file of 78 checks, weighted
toward where a 32-bit big-endian target actually breaks, runs clean on
the PowerBook G4: **78 of 78**.

What it covers, beyond the first file: NaN canonicalization and the
0x7FF8 quiet-NaN bit pattern read back through a DataView, negative zero
through typed arrays, every integer boundary where a 32-bit engine
changes representation (2^31, 2^32, 2^53, and that 9007199254740992 ===
9007199254740993), the full set of shift and bitwise operators at their
edges, all nine typed-array types including Uint8ClampedArray saturation
and BigInt64Array at INT64_MIN, DataView at unaligned offsets, subarray
aliasing versus slice copying, BigInt.asIntN/asUintN round trips, number
formatting in radix 2 through 36, toFixed/toPrecision/toExponential,
surrogate pairs and normalize, property enumeration order with integer
keys, Proxy and Reflect, destructuring, let-closures in loops, RegExp
named groups and sticky and unicode flags, and Date across a negative
epoch.

One check reported a failure and it was the test's fault, not the
engine's: it called [].slice.call on a generator object, which has no
length and so yields an empty array. Generators were then checked
directly - spread, Array.from, manual next(), and for-of all correct.

So the value representation, the whole typed-array and DataView surface,
and the integer/double boundary behaviour are sound on big-endian
PowerPC in 2.52. That is the part that had to be true for the
modern-engine plan to be worth pursuing at all.

### What the emulated G4 can and cannot settle

The PowerEmu Tiger guest is the only G4-class machine here that runs
10.4, so it is the only way to fill the missing cell. But its G4 is
emulated: hw.vectorunit reads 1 because the machine model advertises it,
and AltiVec is implemented in software. That makes the experiment
asymmetric, and the result has to be read accordingly.

If the reproducer **fails there** - the bug appears - that is conclusive.
The fault then happens on Tiger as well as Leopard and is not
OS-specific, and emulation fidelity does not matter, because something
that reproduced has reproduced.

If it **passes**, that is ambiguous and settles nothing. It could mean
the fault is OS-specific, or it could mean the emulated G4 does not
reproduce what a real 7447A does. Nothing inside the guest can tell
those apart. In that case the cell stays open rather than being filled
with a result that might be an artifact, and closing it properly would
need real G4 hardware running Tiger - which does not exist here, since
Sorbet Leopard requires a G4 and the only Tiger machine is the G3.

The fault does look like the kind an emulator should reproduce
faithfully: a JSValue whose two 32-bit halves are read as a double,
which is the optimizing tier mismatching tag and payload order on
big-endian, not anything vector. But that is a reason to expect the
failing case, not a licence to interpret the passing one.

One build note, because it nearly cost the whole experiment: webkit.sh
defaults DFG to OFF, so the first Tiger build came out with
ENABLE_DFG_JIT 0. Running the reproducer against that would have
produced a clean pass and looked exactly like "the bug is
Leopard-specific", when it only meant the tier under test had not been
built. Any build made for this comparison must assert ENABLE_DFG_JIT in
the configured cmakeconfig.h before it is trusted.


## 24 September: the PowerFox comparison, both sides on browserbench.org

PowerFox scored **0.191 +- 0.0051**, against our median of **0.444** over
four runs: **2.3x**. Both were run from https://browserbench.org/Speedometer3.1/
on the same PowerBook G4, caches cleared, nothing else running. The
earlier 0.198 and 0.189 figures were taken against a LAN-served copy of
Speedometer and should not be mixed with these.

Per suite, PowerFox against our run 4, in milliseconds:

| Suite | PowerFox | Polliwog | |
|---|---|---|---|
| TodoMVC-Lit-Complex-DOM | 12834 | 1746 | 7.4x |
| TodoMVC-jQuery | 33723 | 7195 | 4.7x |
| TodoMVC-Preact-Complex-DOM | 2688 | 644 | 4.2x |
| TodoMVC-Svelte-Complex-DOM | 1959 | 523 | 3.7x |
| NewsSite-Next | 14361 | 5432 | 2.6x |
| TodoMVC-WebComponents | 2847 | 1104 | 2.6x |
| TodoMVC-ES6-Webpack-Complex-DOM | 7079 | 2875 | 2.5x |
| TodoMVC-Vue | 3407 | 1469 | 2.3x |
| NewsSite-Nuxt | 12551 | 6030 | 2.1x |
| Perf-Dashboard | 7028 | 3380 | 2.1x |
| TodoMVC-JavaScript-ES5 | 5228 | 2560 | 2.0x |
| Editor-TipTap | 5231 | 2631 | 2.0x |
| Charts-observable-plot | 4172 | 2129 | 2.0x |
| React-Stockcharts-SVG | 8552 | 4389 | 1.9x |
| TodoMVC-Backbone | 3929 | 2115 | 1.9x |
| TodoMVC-React-Complex-DOM | 5728 | 3231 | 1.8x |
| TodoMVC-Angular-Complex-DOM | 5787 | 3344 | 1.7x |
| TodoMVC-React-Redux | 5765 | 3716 | 1.6x |
| Editor-CodeMirror | 1241 | 814 | 1.5x |
| **Charts-chartjs** | **1583** | **3602** | **0.44x** |

**Nineteen of twenty.** The goal set on 2026-09-19 was to beat PowerFox on
every test, and Charts-chartjs is the only one left: PowerFox is 2.3x
faster there, and it is the suite this document has flagged as needing
50% since the beginning. It is canvas rasterization through Core
Graphics, and it is now the single remaining item between here and the
goal.

Worth noting where the wins concentrate. The largest margins - Lit 7.4x,
Preact 4.2x, Svelte 3.7x - are the Complex-DOM suites, which is where
the layout generation work of 20 September paid off. jQuery at 4.7x is
the oldest-style code in the set and the most representative of what
these machines actually browse.

One asymmetry to keep in mind when quoting these: PowerFox's run was
tight, +- 0.0051 on 0.191, about 2.7%. Ours moved from 0.411 to 0.474
across four runs, about 15% run to run, because of collection pauses
that land in individual iterations. The median is the honest figure, and
2x is the figure no reviewer could dispute even against our worst run.

## 24 September: Charts-chartjs is lost in JavaScript, not in the canvas

### The instrument was wrong, and the conclusion survived it

`canvas-paths.html` gave 48.2ms against PowerFox's 99.1 and was read here
as "the rasteriser is not the problem". It does not draw what the suite
draws. Speedometer 3.1's Charts-chartjs is Chart.js 4.2.1 rendering one
**scatter** plot of **5,366 points**, at least twice, and Chart.js's
PointElement.draw assigns strokeStyle, lineWidth and fillStyle from
JavaScript strings on every point before filling and stroking a
translucent circle of radius 3. That is ~43,000 canvas entry points per
pass. canvas-paths.html draws 160 circles with the style hoisted out of
the loop, in opaque colours, and spends most of its time on area fills
and polylines a scatter plot never draws.

`canvas-scatter.html` reproduces the real inner loop. On the PowerBook
G4, milliseconds per pass:

| | Polliwog | PowerFox |
|---|---|---|
| per-point style (the real loop) | **372** | 546 |
| style hoisted out | 362 | 476 |
| fill only, no stroke | 181 | 378 |
| opaque instead of translucent | 357 | 473 |
| style assignment, no drawing | **5** | 32 |

So the conclusion holds on a correct instrument: we are 1.5x faster than
PowerFox at the real loop, 2.1x on fill alone, and 6.4x on the style
assignments themselves - the one-entry memo in setFillColor earning its
keep. The old number was right by accident; this one is right on
purpose.

### Where the suite's time actually goes

Two draw passes put ~744ms of our 3602 in the canvas, and ~1092ms of
PowerFox's 1583. Everything else is **2858ms against 491ms, a 5.8x
gap**, and all of it JavaScript. PowerFox spends most of its time in
this suite drawing; we spend most of ours running Chart.js.

`js-kernels.html`, whose results had never been recorded, agrees at
3.6x overall. Milliseconds:

| kernel | Polliwog | PowerFox | ratio |
|---|---|---|---|
| closure-callback | 81 | 4 | 20x |
| object-literal-options | 108 | 6 | 18x |
| array-numeric | 238 | 16 | 15x |
| polymorphic-call | 77 | 16 | 4.8x |
| array-higher-order | 840 | 220 | 3.8x |
| monomorphic-property | 377 | 106 | 3.6x |
| float-math | 684 | 258 | 2.7x |
| string-build | 182 | 102 | 1.8x |
| **total** | **2587** | **728** | **3.6x** |

array-higher-order and float-math are 1046ms of the 1859ms gap between
those totals.

### Five findings in JavaScriptCore, none of which need an optimising tier

A source audit found specific causes for exactly those kernels, which is
the reason to believe it: it predicted the shape of the table above
without seeing it.

1. **Baseline code still updates ArithProfile.** `jit/JITMathIC.h:148`
   sets `shouldEmitProfiling = !isOptimizingJIT(codeBlock->jitType())`,
   which is true for baseline, and it is a different flag from the one
   ENABLE_DFG_JIT=OFF compiles out. Every double multiply carries 20-25
   instructions and two or three stores to one global - a load-hit-store
   stall each time on the 7447. `emit_op_div` gates on
   `JIT::shouldEmitProfiling()` instead and is clean, which is the proof.
   Two edits.
2. **The PPC inline caches are 72 bytes and the sequence is 32-36.**
   Patch 0049 took MIPS's numbers verbatim. Every filled monomorphic
   access runs its code and then falls through about ten nops, on a 32KB
   I-cache. x86-64 uses 23 bytes, ARM64 40.
   `InlineAccess::dumpCacheSizesAndCrash()` exists to measure it.
3. **`i in array` is a C++ call per element.** ArrayPrototype.js runs it
   in forEach, map, filter, every, some, reduce and find; `op_in` is
   DEFINE_SLOW_OP with no fast path, and already carries an ArrayProfile
   the baseline never reads. `emit_op_has_indexed_property` is a working
   model for the fix, about 80 lines.
4. **Six Math thunks are dead on PowerPC.** The fallback arm of
   `defineUnaryDoubleOpWrapper` is 0 and there is no CPU(PPC) arm, so
   Math.round, floor, ceil, exp, log and trunc take the full host-call
   path. fpRegT0 is already argumentFPR0 and returnValueFPR on PPC, the
   same condition that lets ARM64 define the wrapper as a tail branch.
   min and max have no thunks at all.
5. **Doubles round-trip through the red zone.** `moveDoubleToInts` is
   stfd plus two lwz; `moveIntsToDouble` is two stw plus lfd. Both defeat
   store-to-load forwarding on the 7447. One `fadd` costs eleven memory
   operations and three stalls, when on big-endian a boxed double in a
   frame slot *is* the IEEE double and lfd/stfd would do - which
   `emitLoadDouble`/`emitStoreDouble` already know, and which
   `emitBinaryDoubleOp` still does for the jless family.

Order to attack: 1, 2 and 4 first - hours each, near-zero risk,
independent of one another - then 3, then 5. None of them is the
optimising tier, and all of them help every suite, not only this one.

### Three of the five fixed, and what they were actually worth

Items 1, 2 and 4 are done. Measured on the PowerBook G4 with jsc, the
same binary configuration on both sides (ENABLE_DFG_JIT 0, which is what
the G4 ships), five runs each, medians:

| kernel | before | after | |
|---|---|---|---|
| float-math | 672 | 625 | -7.0% |
| object-literal-options | 103 | 100 | -2.9% |
| polymorphic-call | 84 | 82 | -2.4% |
| monomorphic-property | 376 | 371 | -1.3% |
| **total** | **2571** | **2501** | **-2.7%** |

Correctness is unchanged: the 78-check probe gives 72 pass and 6 fail on
both builds, the same six - five BigInt features 604 does not have
(BigInt64Array, asIntN, asUintN, setBigUint64, and shifts beyond 64
bits) and one bug in the test itself. No regression from any of the
three.

What each was worth, honestly:

**Item 1, the ArithProfile flag, is the one that paid.** 7% on the
kernel made of double arithmetic, reproducibly, with tight spreads on
both sides (625-638 against 666-676). Two lines.

**Item 2, the inline cache sizes, did not - on this instrument.** The
measurement itself was worth having: `dumpCacheSizesAndCrash` on the G4
reports array length 32, inline offset 40, out of line offset 44,
replace 40, replace out of line 44. The constants were 72, 72 and 56,
inherited from MIPS. They are now 44, 44 and 32, which is 28 bytes of
nops removed from every property access site. That is 1.3% on
monomorphic-property, far less than the framing suggested. The likely
reason is that nops retire cheaply and a microbenchmark's code is
resident anyway, so a kernel cannot see a footprint change. That is a
testable claim rather than an excuse, and the test is a real page.

**Item 4, the Math thunks, cannot be separated from item 1 here.** The
float-math kernel exercises general double arithmetic as well as Math
calls, and both changes land in it. Most of the 7% is likely item 1,
which removes work from every double multiply, against thunks that help
only round, floor, ceil, exp, log and trunc. Unproven either way.

**The variance result may matter more than the medians.** Before: 2541
to 2609. After: 2499 to 2510. The spread collapsed, which is what a
smaller instruction footprint should do, and it is the one signal in
these numbers that points at item 2 working as intended.

One correctness hazard found on the way, which the source audit flagged
and which would not have failed loudly: `callDoubleToDoublePreservingReturn`
does not reserve a linkage area, and a Darwin PowerPC callee writes into
the 56 bytes above sp before doing anything else. Enabling the Math
thunks without fixing that would have put the callee's saved lr into our
frame header on the first Math.floor of a double.

### The A/B, on one machine, one morning

The kernel numbers said three per cent and the first suite runs looked
like a regression on the very suite the work was aimed at. Both readings
were wrong, and for the same reason: they compared against a run taken
the day before. Swapping the engine back and forth on the PowerBook
within the hour, everything else held still, gives:

| | old engine | fixed engine | |
|---|---|---|---|
| Speedometer 3.1 score | 0.436 | **0.464**, twice | +6.4% |
| geomean | 2296ms | **2155 / 2157ms** | -6.1% |
| geomean confidence | 3.7% | **1.7% / 2.5%** | |
| Charts-chartjs | 3941ms | **3692 / 3820ms** | -4.7% |

Charts-chartjs improved. The earlier reading of +2.5% came from
comparing against 3602ms in run 4 of the day before, which was a fast
outlier for that suite; the same-day baseline is 3941ms. A suite whose
own confidence interval is 18% cannot be compared across days at all,
and doing it produced a confident statement in the wrong direction.

**The reproducibility is the better result.** Two consecutive runs
scored 0.464 and 0.464, with geomeans of 2154.71 and 2157.08 - a tenth
of a per cent apart - where the four runs before the fixes ranged from
0.411 to 0.474. The engine did not only get faster, it stopped varying.
That is what a smaller instruction footprint should do, it is the one
thing the kernels also showed (2541-2609 before, 2499-2510 after), and
it is worth more to someone using the browser than the six per cent is:
a page that takes the same time every time feels different from one that
takes anywhere in a 15% band.

Charts-chartjs is still lost. 3756ms against PowerFox's 1583ms is 2.4x,
where it was 2.3x before - the fixes moved our number and not the gap.
What closes it is item 3 or item 5, or the optimising tier.

## 24 September: spike A closes, on both machines

The toolchain question the plan put before everything else - can GCC 14
build large C++23 code for powerpc-apple-darwin9 *and* darwin8, and does
it run - is answered yes. `engine/tests/spike-a.cpp` uses the pieces
WebCore-scale code actually needs and JSCOnly does not: exceptions
thrown through eight frames with destructors that must run while the
stack unwinds, std::format, four threads incrementing a std::atomic,
std::call_once, a unique_ptr moved across a thread boundary,
steady_clock, and an exception captured on one thread and rethrown on
another.

    Leopard 10.5.9, PowerBook G4      8 of 8, dynamic runtime
    Tiger 10.4.11, Pismo G3 500MHz    8 of 8, static runtime

std::call_once passing is the one to note. Emulated TLS has broken this
port before through exactly that construct, and it is why the engine
bundles one shared libstdc++ rather than a static copy per image.

**Tiger will not load a bundled libstdc++ by @executable_path.** The
dynamically linked build runs on Leopard and fails on Tiger, and
DYLD_PRINT_LIBRARIES says why: dyld loads /usr/lib/libstdc++.6.dylib -
the system's 2007 copy, which has no std::thread - rather than the one
beside the executable, and DYLD_LIBRARY_PATH does not override it. The
same binary with -static-libstdc++ -static-libgcc passes everything.

That is a packaging constraint rather than a language one, and it is
specific to plain dylibs: the engine reaches its own frameworks through
DYLD_FRAMEWORK_PATH, which does work on Tiger, and that is how the
shipped Tiger engine loads at all. Worth knowing before spike C, because
an out-of-tree WebKitLegacy will want the same treatment, and because
"static runtime per image" is the thing that breaks std::call_once once
there is more than one image.

Spike B is answered too: 2.52's JavaScriptCore builds, runs on both
systems, and is correct on big-endian, 78 checks of 78 where 604 manages
72. CLoop against 604's baseline JIT is 2.4x to 4.5x on tight loops but
only 1.5x on a mixed set, because anything dominated by the engine's own
native code barely moves. The plan's fallback - "if CLoop is unusable,
invest in speed instead of a newer engine" - is not needed.

Which leaves spike C, first paint, as the next gate and the first one
that is months rather than hours.

### The reproducer, checked against the cell that is supposed to be correct

The Tiger engine is rebuilt with items 2 and 4 - item 1 is deliberately
inert there, because the optimizing tier is on for Tiger and a G3 and so
ArithProfile has a real reader.

Two things were verified on the Pismo before trusting it.

**The inline cache sizes are the same on a G3 as on a G4.** They were
measured on the PowerBook and set from that, which is how a wrong
constant ships. POLLIWOG_dumpInlineCacheSizes on the 500MHz Pismo gives
array length 32, inline offset 40, out of line offset 44, replace 40,
replace out of line 44 - identical. The MacroAssembler sequences do not
vary with -mcpu, as expected, and now that is checked rather than
assumed.

**The DFG reproducer passes on Tiger and a G3**, with the tier on:

    function build(n){ var a=[]; for (var i=0;i<n;i++) a.push(i); return a.length; }
    var t=0; for (var k=0;k<40;k++) t += build(50000);   // 2,000,000, correct

The same three lines fail on the G4 under Leopard with 'a.push' reading
as 2.121995789e-314. So the one-line reproducer distinguishes both cells
we can already reach, which is what makes it worth pointing at the cell
we cannot: a G4-class processor running Tiger, which exists here only
under PowerEmu.
