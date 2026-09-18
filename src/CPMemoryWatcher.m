/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPMemoryWatcher.h"
#import "CPSettings.h"
#import "CPHTTPCache.h"
#import "CPDebugSnapshot.h"
#include <mach/mach.h>

#define CPCheckInterval   20.0
#define CPMinimumInterval 60.0

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

    if (CPDebugSnapshotPath() != nil)
        NSLog(@"Captain Polliwog: freed WebKit's memory cache (%@)", reason);
}

@end
