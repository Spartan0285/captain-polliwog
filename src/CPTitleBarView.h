/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// The browser window's single top row, as in Safari since version 15: the
// window's close, minimize and zoom buttons share it with the toolbar
// controls. The view sits in the window's frame view, over the standard title
// bar and the top of the content view, draws the bar's background and lets
// the window be dragged (or double-click minimized) by it.
@interface CPTitleBarView : NSView {
}

// Installs a bar of the given height at the top of the window, behind the
// window's own buttons, which it moves down to its middle.
+ (CPTitleBarView *)installInWindow:(NSWindow *)window height:(float)height;

// The right edge of the window's buttons, where the toolbar controls start.
- (float)windowButtonsMaxX;

@end

// A content view that leaves the band under the title bar view to it, so
// clicks there reach the bar (and drag the window).
@interface CPUnifiedContentView : NSView {
    float overlap;
}
- (void)setOverlap:(float)height;
@end
