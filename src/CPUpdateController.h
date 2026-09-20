/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// The Software Update window: what the new version is, what changed in it,
// and a button to install it. It appears when CPUpdater has found something,
// or straight away when the user asks to check.
@interface CPUpdateController : NSObject
{
    NSWindow          *window;
    NSTextField       *headline;
    NSTextField       *detail;
    NSTextView        *notes;
    NSScrollView      *notesScroll;
    NSProgressIndicator *progress;
    NSButton          *installButton;
    NSButton          *laterButton;
}

+ (CPUpdateController *)sharedController;

// Checks, showing the window at once so the user can see it happening.
- (void)checkAsked:(id)sender;
// Shows the window for whatever state the updater is already in.
- (void)show;

@end
