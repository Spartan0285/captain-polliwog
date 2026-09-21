/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// The app's own icon as a drawable image: AppIcon.png from the bundle, since
// -applicationIconImage answers with the Dock's cache and a freshly
// installed app may not be in it yet.
NSImage *CPApplicationIcon(void);

// The first time this browser opens: four things worth doing before the
// first page, each of which is otherwise buried in a menu nobody opens.
//
// Bookmarks brought over, the default browser question asked once rather
// than nagged, a media player recommended on the Macs that can use one, and
// an honest word about this being an alpha with a way to say when it breaks.
//
// It can be skipped from any step and does not come back.
@interface CPWelcome : NSObject
{
    NSWindow    *window;
    NSTextField *heading;
    NSTextField *body;
    NSTextField *result;
    NSTextField *step;
    NSButton    *action;
    NSButton    *nextButton;
    NSButton    *skipButton;
    int          page;
}

// At launch, unless it has been through once already.
+ (void)showIfNeeded;

// From the Help menu, whenever anyone wants it again.
+ (void)show;

// Whether this Mac has a vector unit - the G3 has none, and the PowerPC
// build of VLC that would otherwise be recommended dies on its first frame
// without one.
+ (BOOL)hasAltiVec;

// Starts the download of VLC's last PowerPC build, in this browser rather
// than handing it to another one - the site it is on is among those the
// browser this Mac came with can no longer reach.
+ (void)downloadVLC;

@end
