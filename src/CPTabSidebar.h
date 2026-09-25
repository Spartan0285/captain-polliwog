/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPTab;

// The tabs down the side rather than across the top, as Safari's sidebar
// does. It asks the window the same questions the tab strip does - the
// CPTabBarDataSource methods in CPTabBarView.h - so the window needed no
// new answers.
//
// Titles read properly here: a strip divides its width by the number of
// tabs and truncates, while a column gives every tab the same width
// however many there are, which is the point of having it.
extern const float CPTabSidebarWidth;

@interface CPTabSidebar : NSView
{
    id controller;      // not retained
    int trackingRow;    // row whose close box is being pressed, or -1
}

- (void)setController:(id)aController;

// The height the list wants, so the enclosing scroll view can scroll it.
- (float)heightForTabCount:(unsigned)count;

@end
