/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPHistoryWindow.h"

#import <WebKit/WebKit.h>

#import "CPAppDelegate.h"
#import "CPHistory.h"

// As many as the History menu will ever need to show, and as many as a
// table on a 500MHz G3 can filter without the search field feeling sticky.
#define CPHistoryWindowLimit 2000

@implementation CPHistoryWindow

+ (CPHistoryWindow *)sharedWindow
{
    static CPHistoryWindow *shared = nil;
    if (shared == nil)
        shared = [[CPHistoryWindow alloc] init];
    return shared;
}

- (id)init
{
    NSWindow *window;
    NSRect frame = NSMakeRect(0.0f, 0.0f, 640.0f, 460.0f);
    NSScrollView *scroll;
    NSTableColumn *titleColumn;
    NSTableColumn *urlColumn;
    NSTableColumn *dateColumn;

    window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                                                    NSMiniaturizableWindowMask | NSResizableWindowMask)
                                           backing:NSBackingStoreBuffered
                                             defer:YES];
    [window setTitle:@"History"];
    [window setReleasedWhenClosed:NO];
    [window setMinSize:NSMakeSize(420.0f, 240.0f)];

    self = [super initWithWindow:window];
    if (self == nil) {
        [window release];
        return nil;
    }
    [window release];

    items = [[NSMutableArray alloc] init];
    shown = [[NSMutableArray alloc] init];

    searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(10.0f, frame.size.height - 32.0f, 260.0f, 22.0f)];
    [searchField setAutoresizingMask:NSViewMinYMargin];
    [searchField setTarget:self];
    [searchField setAction:@selector(search:)];
    [[searchField cell] setPlaceholderString:@"Search History"];
    [[window contentView] addSubview:searchField];
    [searchField release];

    countField = [[NSTextField alloc] initWithFrame:NSMakeRect(280.0f, frame.size.height - 29.0f, 240.0f, 16.0f)];
    [countField setAutoresizingMask:(NSViewMinYMargin | NSViewWidthSizable)];
    [countField setEditable:NO];
    [countField setSelectable:NO];
    [countField setBezeled:NO];
    [countField setDrawsBackground:NO];
    [countField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [countField setTextColor:[NSColor colorWithCalibratedWhite:0.35f alpha:1.0f]];
    [[window contentView] addSubview:countField];
    [countField release];

    scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, frame.size.width, frame.size.height - 42.0f)];
    [scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];

    table = [[NSTableView alloc] initWithFrame:[scroll bounds]];
    [table setAllowsMultipleSelection:NO];
    [table setUsesAlternatingRowBackgroundColors:YES];
    [table setRowHeight:16.0f];
    [table setTarget:self];
    [table setDoubleAction:@selector(openSelection:)];

    titleColumn = [[[NSTableColumn alloc] initWithIdentifier:@"title"] autorelease];
    [[titleColumn headerCell] setStringValue:@"Title"];
    [titleColumn setWidth:250.0f];
    [table addTableColumn:titleColumn];

    urlColumn = [[[NSTableColumn alloc] initWithIdentifier:@"url"] autorelease];
    [[urlColumn headerCell] setStringValue:@"Address"];
    [urlColumn setWidth:270.0f];
    [table addTableColumn:urlColumn];

    dateColumn = [[[NSTableColumn alloc] initWithIdentifier:@"date"] autorelease];
    [[dateColumn headerCell] setStringValue:@"Last Visited"];
    [dateColumn setWidth:110.0f];
    [table addTableColumn:dateColumn];

    [table setDataSource:self];
    [table setDelegate:self];
    [scroll setDocumentView:table];
    [table release];
    [[window contentView] addSubview:scroll];
    [scroll release];

    return self;
}

- (void)dealloc
{
    [items release];
    [shown release];
    [super dealloc];
}

- (void)reload
{
    [items setArray:[[CPHistory sharedHistory] recentItems:CPHistoryWindowLimit]];
    [self search:nil];
}

- (void)show
{
    [self reload];
    [[self window] center];
    [self showWindow:self];
    [[self window] makeFirstResponder:searchField];
}

- (IBAction)search:(id)sender
{
    NSString *term = [searchField stringValue];
    unsigned i;

    [shown removeAllObjects];
    if ([term length] == 0) {
        [shown addObjectsFromArray:items];
    } else {
        for (i = 0; i < [items count]; i++) {
            WebHistoryItem *item = [items objectAtIndex:i];
            NSString *title = [item title];
            NSString *url = [item URLString];
            // Case-insensitive on both, because people remember either.
            if ((title != nil && [title rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound)
                || (url != nil && [url rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound))
                [shown addObject:item];
        }
    }
    [countField setStringValue:[NSString stringWithFormat:@"%u of %u", (unsigned)[shown count], (unsigned)[items count]]];
    [table reloadData];
}

- (IBAction)openSelection:(id)sender
{
    int row = [table selectedRow];
    WebHistoryItem *item;

    if (row < 0 || (unsigned)row >= [shown count])
        return;
    item = [shown objectAtIndex:row];
    [(CPAppDelegate *)[NSApp delegate] openAddress:[item URLString]];
}

- (IBAction)clearHistory:(id)sender
{
    [[CPHistory sharedHistory] clear];
    [self reload];
}

#pragma mark Table

- (int)numberOfRowsInTableView:(NSTableView *)view
{
    return (int)[shown count];
}

- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)column row:(int)row
{
    WebHistoryItem *item;
    NSString *identifier = [column identifier];

    if (row < 0 || (unsigned)row >= [shown count])
        return @"";
    item = [shown objectAtIndex:row];
    if ([identifier isEqualToString:@"title"]) {
        NSString *title = [item title];
        return ([title length] > 0) ? title : [item URLString];
    }
    if ([identifier isEqualToString:@"url"])
        return [item URLString];
    if ([identifier isEqualToString:@"date"]) {
        NSTimeInterval when = [item lastVisitedTimeInterval];
        NSDate *date;
        if (when <= 0.0)
            return @"";
        date = [NSDate dateWithTimeIntervalSinceReferenceDate:when];
        return [date descriptionWithCalendarFormat:@"%Y-%m-%d %H:%M" timeZone:nil locale:nil];
    }
    return @"";
}

// Return in the search field opens the first match, which is what a
// search field is for.
- (void)controlTextDidChange:(NSNotification *)notification
{
    [self search:nil];
}

@end
