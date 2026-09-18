/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Frees WebKit's shared memory cache -- decoded images, stylesheets and
// scripts held for every tab at once -- when this Mac runs short. Discarding
// a background tab cannot reach that cache, and on the image-heavy pages
// measured on a 256MB Pismo it is where most of the memory sits.
//
// "Short" means the system has started paging to disk, or free memory has
// dropped below a floor, or the tab budget has just forced a tab out. Pages
// that are still open keep working and re-decode images as they are drawn.
// Can be turned off in Preferences.
@interface CPMemoryWatcher : NSObject
{
    NSTimer            *timer;
    unsigned long long  lastPageouts;
    NSDate             *lastRelief;
}

+ (CPMemoryWatcher *)sharedWatcher;

// Starts or stops watching to match the setting.
- (void)settingsChanged;

// Frees memory now, unless it was done within the last minute or the setting
// is off. The reason is only for the log.
- (void)relieveMemoryPressure:(NSString *)reason;

@end
