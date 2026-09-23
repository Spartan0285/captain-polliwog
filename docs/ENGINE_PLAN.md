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
