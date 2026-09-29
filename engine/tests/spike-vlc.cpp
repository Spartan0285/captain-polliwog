// Spike V: can libvlc live inside this engine's process?
//
// The plan is to make libvlc the media backend behind <video>, which means
// PowerVLC's libraries loaded into the same process as WebCore. Before any
// of that is worth designing, one question has to be answered, and it is the
// question this port has already been wrong about twice:
//
// PowerVLC is built -static-libgcc -static-libstdc++, by a different GCC
// than ours. Our engine carries GCC 6.5's libstdc++.6.dylib and libgcc_s,
// shared, because a static runtime in each image broke std::call_once -
// emulated thread-local storage keeps its state per copy of libgcc, so one
// copy wrote the callable and the other read back a null pointer.
//
// Two C++ runtimes in one process is therefore not a theoretical worry here.
// It should be survivable, because libvlc's interface is pure C and no C++
// object crosses it, but "should" is what the last two failures were built
// on.
//
// So: load libvlc the way the engine would, play something, and while it is
// playing exercise the parts of our own runtime that broke last time -
// call_once, a thread, an exception, a shared_ptr across threads. If those
// still work with VLC's runtime resident, the integration is worth
// designing. If they do not, we have learned it in an afternoon.
//
// Loaded with dlopen rather than linked, which is also how the real thing
// should work: a browser that has no PowerVLC installed must still start.
//
// Built by scripts/toolchain/build-spike-vlc.sh.
#include <atomic>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <dlfcn.h>
#include <unistd.h>

static int failures = 0;

static void check(const char* what, bool ok, const char* detail = 0)
{
    std::printf("  %-34s %-4s %s\n", what, ok ? "ok" : "FAIL", detail ? detail : "");
    if (!ok)
        failures++;
}

// The slice of libvlc this needs. Declared here rather than including
// <vlc/libvlc.h>, so the spike builds on a machine with no VLC installed.
typedef struct libvlc_instance_t libvlc_instance_t;
typedef struct libvlc_media_t libvlc_media_t;
typedef struct libvlc_media_player_t libvlc_media_player_t;

typedef libvlc_instance_t* (*fn_new)(int, const char* const*);
typedef void (*fn_release_instance)(libvlc_instance_t*);
typedef const char* (*fn_get_version)(void);
typedef libvlc_media_t* (*fn_media_new_location)(libvlc_instance_t*, const char*);
typedef libvlc_media_player_t* (*fn_player_new_from_media)(libvlc_media_t*);
typedef int (*fn_player_play)(libvlc_media_player_t*);
typedef void (*fn_player_stop)(libvlc_media_player_t*);
typedef int (*fn_player_is_playing)(libvlc_media_player_t*);
typedef void (*fn_player_release)(libvlc_media_player_t*);
typedef void (*fn_media_release)(libvlc_media_t*);

// --- the parts of our own runtime that failed last time -------------------

static std::once_flag onceFlag;
static int onceRan = 0;

static bool runtimeStillWorks()
{
    bool ok = true;

    // std::call_once, which is the one that broke. Its state lives in
    // emulated TLS, per copy of libgcc.
    std::call_once(onceFlag, []() { onceRan++; });
    std::call_once(onceFlag, []() { onceRan++; });
    ok = ok && (onceRan == 1);

    // A thread that touches a shared_ptr, so the atomic refcount and the
    // thread runtime are both exercised.
    std::shared_ptr<std::vector<int> > shared(new std::vector<int>(1000, 7));
    std::atomic<int> total(0);
    std::thread worker([&total, shared]() {
        int sum = 0;
        for (size_t i = 0; i < shared->size(); i++)
            sum += (*shared)[i];
        total = sum;
    });
    worker.join();
    ok = ok && (total.load() == 7000);

    // An exception across a function boundary: two unwinders in one process
    // is the other way this could go wrong.
    try {
        throw std::runtime_error("expected");
    } catch (const std::exception& e) {
        ok = ok && (std::strcmp(e.what(), "expected") == 0);
    } catch (...) {
        ok = false;
    }
    return ok;
}

int main(int argc, char** argv)
{
    const char* libraryPath = argc > 1 ? argv[1]
        : "/Applications/PowerVLC.app/Contents/MacOS/lib/libpowervlc.dylib";
    const char* mediaURL = argc > 2 ? argv[2] : 0;
    char detail[512];

    std::printf("spike V: libvlc inside this engine's process\n");

    // Our runtime, before VLC is anywhere near the process. If this is
    // already broken the rest means nothing.
    check("our C++ runtime, before", runtimeStillWorks());

    // RTLD_GLOBAL, not RTLD_LOCAL, and not by preference. libvlc finds its
    // own data directory by calling dladdr() on one of its internal
    // functions and abort()s if that returns nothing, and on Leopard's dyld
    // dladdr does not answer for an image loaded privately. The cost is that
    // VLC's symbols join the global namespace, where they could answer for
    // ours; the alternative is that libvlc_new cannot start at all.
    int mode = getenv("CP_VLC_LOCAL") ? (RTLD_LAZY | RTLD_LOCAL)
                                      : (RTLD_LAZY | RTLD_GLOBAL);
    void* handle = dlopen(libraryPath, mode);
    std::snprintf(detail, sizeof detail, "%s", handle ? libraryPath : dlerror());
    check("dlopen libvlc", handle != 0, detail);
    if (!handle)
        return failures;

    // RTLD_LOCAL above matters: VLC's symbols should not be promoted into
    // the global namespace, where they could answer for ours.
    fn_get_version get_version = (fn_get_version)dlsym(handle, "libvlc_get_version");
    fn_new vlc_new = (fn_new)dlsym(handle, "libvlc_new");
    fn_release_instance vlc_release = (fn_release_instance)dlsym(handle, "libvlc_release");
    check("resolve libvlc_new", vlc_new != 0);
    check("resolve libvlc_get_version", get_version != 0);
    if (!vlc_new)
        return failures;

    if (get_version)
        std::printf("  libvlc version                     %s\n", get_version());

    check("our C++ runtime, after dlopen", runtimeStillWorks());

    // A real instance. --intf dummy and no video output: this is about
    // whether the library lives here, not about drawing yet.
    // Verbose on purpose: when libvlc_new fails it aborts, and the reason
    // is on stderr a moment before. --quiet hid it for an afternoon.
    const char* args[] = { "--intf", "dummy", "--vout", "dummy",
                           "--aout", "dummy", "--no-video-title-show",
                           "-vv" };
    libvlc_instance_t* instance = vlc_new(sizeof args / sizeof args[0], args);
    check("libvlc_new", instance != 0);
    if (!instance)
        return failures;

    check("our C++ runtime, with libvlc up", runtimeStillWorks());

    if (mediaURL) {
        fn_media_new_location media_new =
            (fn_media_new_location)dlsym(handle, "libvlc_media_new_location");
        fn_player_new_from_media player_new =
            (fn_player_new_from_media)dlsym(handle, "libvlc_media_player_new_from_media");
        fn_player_play play = (fn_player_play)dlsym(handle, "libvlc_media_player_play");
        fn_player_is_playing is_playing =
            (fn_player_is_playing)dlsym(handle, "libvlc_media_player_is_playing");
        fn_player_stop stop = (fn_player_stop)dlsym(handle, "libvlc_media_player_stop");
        fn_player_release player_release =
            (fn_player_release)dlsym(handle, "libvlc_media_player_release");
        fn_media_release media_release =
            (fn_media_release)dlsym(handle, "libvlc_media_release");

        check("resolve the player API",
              media_new && player_new && play && is_playing && stop);
        if (media_new && player_new && play) {
            libvlc_media_t* media = media_new(instance, mediaURL);
            libvlc_media_player_t* player = media ? player_new(media) : 0;
            check("libvlc_media_player_new", player != 0);
            if (player) {
                check("libvlc_media_player_play", play(player) == 0);
                // Give it long enough to open the stream and start decoding,
                // and run our runtime checks while it is working, which is
                // the moment both runtimes are actually busy at once.
                bool started = false;
                for (int i = 0; i < 30; i++) {
                    sleep(1);
                    if (is_playing && is_playing(player)) { started = true; break; }
                }
                std::snprintf(detail, sizeof detail, "%s", started ? "playing" : "never started");
                check("stream opened", started, detail);
                check("our C++ runtime, while decoding", runtimeStillWorks());
                if (stop) stop(player);
                if (player_release) player_release(player);
            }
            if (media && media_release) media_release(media);
        }
    }

    if (vlc_release) vlc_release(instance);
    check("our C++ runtime, after teardown", runtimeStillWorks());

    std::printf("  %s\n", failures ? "FAILURES" : "all stages passed");
    return failures;
}
