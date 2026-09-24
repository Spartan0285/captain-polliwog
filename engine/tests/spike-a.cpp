// Spike A of docs/ENGINE_PLAN.md: can GCC 14 build large C++23 code for
// powerpc-apple-darwin, and does it RUN on both Tiger and Leopard?
//
// JSCOnly does not answer this. It is built -fno-exceptions, uses no
// <format>, and starts no threads. WebCore does all three, so this is
// the gate before spike C rather than after it.
#include <atomic>
#include <chrono>
#include <exception>
#include <format>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <cstdio>

static int failures = 0;
static void check(const char* what, bool ok)
{
    std::printf("  %-28s %s\n", what, ok ? "ok" : "FAIL");
    if (!ok)
        failures++;
}

struct Thrown : std::runtime_error {
    explicit Thrown(const std::string& s) : std::runtime_error(s) { }
};

// A destructor that must run while the stack unwinds. On Tiger the
// Objective-C runtime raises through longjmp and skips these; the C++
// unwinder must not.
struct Guard {
    bool& flag;
    explicit Guard(bool& f) : flag(f) { }
    ~Guard() { flag = true; }
};

static void throwsDeep(int depth)
{
    bool unwound = false;
    Guard g(unwound);
    if (depth > 0)
        throwsDeep(depth - 1);
    throw Thrown(std::format("from depth {}", depth));
}

int main()
{
    std::printf("spike A: C++23 on this system\n");

    // 1. Exceptions, through several frames, with destructors.
    {
        bool caught = false;
        std::string msg;
        try {
            throwsDeep(8);
        } catch (const Thrown& e) {
            caught = true;
            msg = e.what();
        } catch (...) {
            caught = false;
        }
        check("exceptions unwind", caught);
        check("exception carries message", msg == "from depth 0");
    }

    // 2. std::format, which is the newest library piece WebCore-scale
    //    code is likely to reach for.
    {
        std::string s = std::format("{} {:.2f} {:#x} {:>6}", "x", 3.14159, 255, "r");
        check("std::format", s == "x 3.14 0xff      r");
    }

    // 3. Threads and atomics. Big-endian is irrelevant to correctness
    //    here, but emulated TLS is not: every image must share one copy.
    {
        std::atomic<long> counter{0};
        std::vector<std::thread> threads;
        for (int i = 0; i < 4; i++)
            threads.emplace_back([&counter] {
                for (int j = 0; j < 20000; j++)
                    counter.fetch_add(1, std::memory_order_relaxed);
            });
        for (auto& t : threads)
            t.join();
        check("threads + atomics", counter.load() == 80000);
    }

    // 4. thread_local, which is emulated TLS on this target and has
    //    already broken this port once through std::call_once.
    {
        static std::once_flag once;
        int runs = 0;
        for (int i = 0; i < 5; i++)
            std::call_once(once, [&runs] { runs++; });
        check("std::call_once", runs == 1);
    }

    // 5. Smart pointers and move semantics across a thread boundary.
    {
        auto p = std::make_unique<std::vector<int>>(1000, 7);
        std::unique_ptr<std::vector<int>> moved;
        std::thread t([&p, &moved] { moved = std::move(p); });
        t.join();
        check("unique_ptr move", p == nullptr && moved && (*moved)[999] == 7);
    }

    // 6. chrono, which WebCore uses for every timer.
    {
        auto start = std::chrono::steady_clock::now();
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        check("steady_clock + sleep", ms >= 40 && ms < 2000);
    }

    // 7. An exception thrown on one thread and observed on another,
    //    which is how a real engine reports a failure out of a worker.
    {
        std::exception_ptr captured;
        std::thread t([&captured] {
            try {
                throw Thrown("from a thread");
            } catch (...) {
                captured = std::current_exception();
            }
        });
        t.join();
        bool ok = false;
        try {
            if (captured)
                std::rethrow_exception(captured);
        } catch (const Thrown& e) {
            ok = std::string(e.what()) == "from a thread";
        } catch (...) { }
        check("exception across threads", ok);
    }

    std::printf("%s (%d failure%s)\n", failures ? "FAILED" : "all passed",
                failures, failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
