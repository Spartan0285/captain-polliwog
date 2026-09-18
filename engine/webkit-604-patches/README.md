# Captain Polliwog changes to WebKit 604

Applied in order on top of:

1. Apple's WebKit tag `Safari-604.5.6` (github.com/WebKit/WebKit), with only
   `Source`, `Tools` and `WebKitLibraries` checked out.
2. Leopard WebKit's patch `WebKit_604.5.6.diff`, from
   `604/Sources/Patches_604.5.6.tar.bz2` at sourceforge.net/projects/leopard-webkit
   (Tobias Netzel).

```
git am /path/to/engine/webkit-604-patches/*.patch
```

They make WebKit's CMake "Mac" port reproduce Leopard WebKit's Xcode build,
so it can be cross-compiled from Linux with the toolchain in
`scripts/toolchain/`. See `docs/ENGINE_PLAN.md` for the why.
