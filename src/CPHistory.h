/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class WebHistory;

// Browsing history, kept by WebKit's own WebHistory so that visited links are
// coloured as visited, and saved to Application Support between launches.
// Every entry stays in memory, so the length is capped by the memory budget.
@interface CPHistory : NSObject
{
    WebHistory *history;
}

+ (CPHistory *)sharedHistory;

- (void)start;
- (void)save;
- (void)clear;

// Most recent first, skipping Captain Polliwog's own start page.
- (NSArray *)recentItems:(unsigned)count;

@end
