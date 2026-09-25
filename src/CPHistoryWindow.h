/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Command-Y: everything in history, searchable, rather than the last
// handful the History menu lists.
@interface CPHistoryWindow : NSWindowController
{
    NSTableView   *table;
    NSSearchField *searchField;
    NSTextField   *countField;
    NSMutableArray *items;      // WebHistoryItem, most recent first
    NSMutableArray *shown;      // the ones matching the search
}

+ (CPHistoryWindow *)sharedWindow;

- (void)show;
- (IBAction)search:(id)sender;
- (IBAction)openSelection:(id)sender;
- (IBAction)clearHistory:(id)sender;

@end
