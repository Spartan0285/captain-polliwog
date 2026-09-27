/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPMemoryWatcher.h"
#import "CPSettings.h"
#import "CPHTTPCache.h"
#import "CPDebugSnapshot.h"
#import "CPAppDelegate.h"
#include <mach/mach.h>

#define CPCheckInterval   20.0
#define CPMinimumInterval 60.0
// Rounds of cache-emptying and tab-discarding to try before giving up and
// stopping the foreground page's scripts. Three, at a minute apart, so a
// page that is merely slow to settle is never silenced.
#define CPReliefsBeforeStoppingScripts 3

static BOOL CPReadVMStatistics(vm_statistics_data_t *statistics)
{
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    return host_statistics(mach_host_self(), HOST_VM_INFO,
                           (host_info_t)statistics, &count) == KERN_SUCCESS;
}

// Below this much free memory the page-out daemon is about to start work.
static unsigned long long CPFreeMemoryFloor(void)
{
    switch ([[CPSettings sharedSettings] effectiveMemoryProfile]) {
    case CPMemoryProfileSmall:  return 16ULL * 1024 * 1024;
    case CPMemoryProfileMedium: return 32ULL * 1024 * 1024;
    default:                    return 48ULL * 1024 * 1024;
    }
}

// WebCoreStatistics is WebKit's own class, with no header in the 10.4 SDK
// to import, so its methods are declared here and the class is looked up by
// name. Everything below checks respondsToSelector before calling: a build
// of WebKit without it must keep working, just with less to release.
@interface CPWebCoreStatistics : NSObject
+ (size_t)javaScriptObjectsCount;
+ (void)garbageCollectJavaScriptObjects;
+ (void)purgeInactiveFontData;
@end

@interface CPMemoryWatcher (Private)
- (void)check:(NSTimer *)aTimer;
@end

@implementation CPMemoryWatcher (Private)

- (void)check:(NSTimer *)aTimer
{
    vm_statistics_data_t statistics;
    unsigned long long freeBytes;
    BOOL pagedOut;

    if (!CPReadVMStatistics(&statistics))
        return;
    freeBytes = (unsigned long long)statistics.free_count * vm_page_size;
    pagedOut = (lastPageouts != 0 && statistics.pageouts > lastPageouts);
    lastPageouts = statistics.pageouts;

    if (pagedOut)
        [self relieveMemoryPressure:@"the system is paging to disk"];
    else if (freeBytes < CPFreeMemoryFloor())
        [self relieveMemoryPressure:[NSString stringWithFormat:@"only %.0f MB free",
                                     (double)freeBytes / (1024.0 * 1024.0)]];
    else if (freeBytes > CPFreeMemoryFloor() * 4)
        // Comfortable again: forget that we were ever struggling, so a quiet
        // hour does not leave the escalation primed for the next page.
        consecutiveReliefs = 0;
}

@end

@implementation CPMemoryWatcher

+ (CPMemoryWatcher *)sharedWatcher
{
    static CPMemoryWatcher *watcher = nil;
    if (watcher == nil)
        watcher = [[CPMemoryWatcher alloc] init];
    return watcher;
}

- (void)dealloc
{
    [timer invalidate];
    [timer release];
    [lastRelief release];
    [super dealloc];
}

- (void)settingsChanged
{
    vm_statistics_data_t statistics;
    BOOL wanted = [[CPSettings sharedSettings] releasesMemoryUnderPressure];

    if (wanted && timer == nil) {
        if (CPReadVMStatistics(&statistics))
            lastPageouts = statistics.pageouts;
        timer = [[NSTimer scheduledTimerWithTimeInterval:CPCheckInterval
                                                  target:self
                                                selector:@selector(check:)
                                                userInfo:nil
                                                 repeats:YES] retain];
    } else if (!wanted && timer != nil) {
        [timer invalidate];
        [timer release];
        timer = nil;
    }
}

- (void)relieveMemoryPressure:(NSString *)reason
{
    Class webCache = NSClassFromString(@"WebCache");
    Class stats = NSClassFromString(@"WebCoreStatistics");
    size_t before = 0;
    unsigned discarded;

    if (![[CPSettings sharedSettings] releasesMemoryUnderPressure])
        return;
    if (lastRelief != nil && -[lastRelief timeIntervalSinceNow] < CPMinimumInterval)
        return;
    [lastRelief release];
    lastRelief = [[NSDate date] retain];

    // WebCache is not in the 10.4 SDK, but has been in WebKit since Safari 3.
    // +empty drops cached resources no open page is using, and the decoded
    // images of those that are; open pages redraw from the original data.
    if ([webCache respondsToSelector:@selector(empty)])
        [webCache performSelector:@selector(empty)];
    [CPHTTPCache emptyMemoryCache];

    consecutiveReliefs++;

    // Background tabs next. Every one that can go, not just enough to meet
    // the tab budget: under this much pressure the budget is not what is
    // binding. This deliberately calls the delegate's pressure-specific
    // method and not enforceLiveTabLimit, which relieves pressure itself and
    // would call straight back into here.
    discarded = [(CPAppDelegate *)[NSApp delegate] discardBackgroundTabsUnderMemoryPressure];

    // Only now is collecting worth the pause. A discarded tab's objects stay
    // reachable until its WebView is gone, which is why running the collector
    // on its own achieved nothing measurable on Vimeo: the million Arrays it
    // holds are not garbage while the page is alive.
    if ([stats respondsToSelector:@selector(javaScriptObjectsCount)])
        before = [(Class)stats javaScriptObjectsCount];
    if ([stats respondsToSelector:@selector(garbageCollectJavaScriptObjects)])
        [(Class)stats garbageCollectJavaScriptObjects];
    // Glyphs for fonts nothing is drawing with any more. Small next to the
    // heap, but free.
    if ([stats respondsToSelector:@selector(purgeInactiveFontData)])
        [(Class)stats purgeInactiveFontData];

    // Still here after three rounds of all that, so the page in front is the
    // one eating the machine and nothing we own will get it back. Stop its
    // scripts; it is the last thing short of being killed.
    if (consecutiveReliefs >= CPReliefsBeforeStoppingScripts) {
        if ([(CPAppDelegate *)[NSApp delegate] stopScriptsInForegroundTabsUnderMemoryPressure])
            consecutiveReliefs = 0;
    }

    if (CPDebugLogging()) {
        size_t after = [stats respondsToSelector:@selector(javaScriptObjectsCount)]
                     ? [(Class)stats javaScriptObjectsCount] : 0;
        NSLog(@"Captain Polliwog: released memory (%@); %u tabs discarded; "
               "JavaScript objects %lu -> %lu; round %u",
              reason, discarded, (unsigned long)before, (unsigned long)after,
              consecutiveReliefs);

    }
}

@end
