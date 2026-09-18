/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPHistory.h"
#import "CPSettings.h"
#import <WebKit/WebKit.h>

#define CPSaveDelay 10.0

@interface CPHistory (Private)
- (NSURL *)fileURL;
- (void)itemsAdded:(NSNotification *)notification;
@end

@implementation CPHistory (Private)

- (NSURL *)fileURL
{
    return [NSURL fileURLWithPath:[[[CPSettings sharedSettings] supportDirectory]
                                   stringByAppendingPathComponent:@"History.plist"]];
}

// Writing the whole history on every page would be real disk work on a G3,
// so saves are batched a few seconds after browsing settles.
- (void)itemsAdded:(NSNotification *)notification
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];
    [self performSelector:@selector(save) withObject:nil afterDelay:CPSaveDelay];
}

@end

@implementation CPHistory

+ (CPHistory *)sharedHistory
{
    static CPHistory *shared = nil;
    if (shared == nil)
        shared = [[CPHistory alloc] init];
    return shared;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [history release];
    [super dealloc];
}

- (void)start
{
    NSError *error = nil;

    if (history != nil)
        return;
    history = [[WebHistory alloc] init];
    [history setHistoryItemLimit:(int)[[CPSettings sharedSettings] historyItemLimit]];
    [history setHistoryAgeInDaysLimit:30];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[[self fileURL] path]])
        [history loadFromURL:[self fileURL] error:&error];
    [WebHistory setOptionalSharedHistory:history];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemsAdded:)
                                                 name:WebHistoryItemsAddedNotification object:history];
}

- (void)save
{
    NSError *error = nil;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];
    if (history != nil && ![history saveToURL:[self fileURL] error:&error])
        NSLog(@"Captain Polliwog: could not save history: %@", [error localizedDescription]);
}

- (void)clear
{
    [history removeAllItems];
    [self save];
}

- (NSArray *)recentItems:(unsigned)count
{
    NSMutableArray *items = [NSMutableArray array];
    NSArray *days = [history orderedLastVisitedDays];
    unsigned dayIndex;
    unsigned index;

    for (dayIndex = 0; dayIndex < [days count] && [items count] < count; dayIndex++) {
        NSArray *dayItems = [history orderedItemsLastVisitedOnDay:[days objectAtIndex:dayIndex]];
        for (index = 0; index < [dayItems count] && [items count] < count; index++) {
            WebHistoryItem *item = [dayItems objectAtIndex:index];
            if ([[item URLString] hasPrefix:@"file:"])
                continue;
            [items addObject:item];
        }
    }
    return items;
}

@end
