/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPTab;

// What the tab bar asks of the window it belongs to.
@interface NSObject (CPTabBarDataSource)
- (NSArray *)tabsForTabBar;
- (CPTab *)selectedTabForTabBar;
- (void)tabBarSelectTab:(CPTab *)tab;
- (void)tabBarCloseTab:(CPTab *)tab;
- (void)tabBarNewTab;
@end

// A plain, cheap-to-draw tab strip: flat fills and text only, since every
// redraw costs real time on a G3. Discarded tabs are drawn in grey.
@interface CPTabBarView : NSView
{
    id controller;      // not retained
}

- (void)setController:(id)aController;

@end
