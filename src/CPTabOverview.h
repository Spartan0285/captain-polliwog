/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPTab;

// What the overview asks of the window it belongs to. The same window that
// answers CPTabBarView, in practice.
@interface NSObject (CPTabOverviewOwner)
- (NSArray *)tabsForTabBar;
- (CPTab *)selectedTabForTabBar;
- (void)tabBarSelectTab:(CPTab *)tab;
- (void)tabBarCloseTab:(CPTab *)tab;
- (void)tabBarNewTab;
@end

// Every tab at once, as a grid of thumbnails: pick one, close one, or close
// them all. Safari's tab overview, on a machine where taking the pictures is
// the expensive part - so each is taken once, when the overview opens, and
// only for tabs that still have a web view (a discarded tab draws its title
// on a plain card instead of being woken up to be photographed).
@interface CPTabOverview : NSView
{
    id              controller;     // not retained
    NSArray        *shownTabs;
    NSMutableArray *thumbnails;     // NSImage, or NSNull for a discarded tab
    int             hoveredIndex;
    int             hoveredClose;   // the index whose close box is under the mouse
    NSButton       *closeAllButton;
    NSButton       *newTabButton;
}

// Puts the overview over the window's content, taking the pictures as it
// goes, or takes it away again. Answers whether it is showing afterwards.
+ (BOOL)toggleInWindow:(NSWindow *)window controller:(id)aController;
+ (BOOL)isShowingInWindow:(NSWindow *)window;
+ (void)hideInWindow:(NSWindow *)window;

@end
