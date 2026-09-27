/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Frees memory when this Mac runs short, in three steps, because one step
// is not enough for every way a machine runs out.
//
// First WebKit's shared memory cache -- decoded images, stylesheets and
// scripts held for every tab at once. On the image-heavy pages measured on a
// 256MB Pismo that is where most of the memory sits, and discarding a
// background tab cannot reach it.
//
// Then the background tabs themselves, every one that can go rather than
// just enough to meet the tab budget: under real pressure the budget is not
// what is binding, the machine is. A discarded tab's JavaScript objects only
// become collectable once its WebView is gone, so the collector runs after
// this and not before -- measured on Vimeo, collecting first reclaims almost
// nothing, because the objects are still reachable from a live page.
//
// Last, if pressure survives all of that, the scripts in the page actually
// being looked at. Vimeo left open on a 2GB G4 reaches 1.7GB, in plain
// Arrays and Objects the page is holding on purpose, and no amount of
// releasing our own memory touches it. A page that stops updating is worse
// than one that works and better than an application the system kills, which
// is what happens otherwise: killed, with no crash report to explain it.
// Navigating or reloading turns scripts back on, because CPTab sets
// JavaScript from CPSiteSettings on every load.
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
    unsigned            consecutiveReliefs;
}

+ (CPMemoryWatcher *)sharedWatcher;

// Starts or stops watching to match the setting.
- (void)settingsChanged;

// Frees memory now, unless it was done within the last minute or the setting
// is off. The reason is only for the log.
- (void)relieveMemoryPressure:(NSString *)reason;

@end
