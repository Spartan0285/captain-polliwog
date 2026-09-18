/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

extern NSString * const CPBookmarksDidChangeNotification;

// A bookmark, or a folder of them when it has children. A class rather than a
// dictionary so that two bookmarks with the same title and address are still
// different items to the outline view that edits them.
@interface CPBookmark : NSObject
{
    NSString       *title;
    NSString       *URLString;
    NSMutableArray *children;   // nil for a plain bookmark
    CPBookmark     *parent;     // not retained
}

+ (CPBookmark *)bookmarkWithTitle:(NSString *)aTitle URLString:(NSString *)aURLString;
+ (CPBookmark *)folderWithTitle:(NSString *)aTitle;

- (NSString *)title;
- (void)setTitle:(NSString *)aTitle;
- (NSString *)URLString;
- (void)setURLString:(NSString *)aURLString;
- (BOOL)isFolder;
- (NSArray *)children;
- (CPBookmark *)parent;

- (void)insertChild:(CPBookmark *)child atIndex:(unsigned)index;
- (void)addChild:(CPBookmark *)child;
- (void)removeChild:(CPBookmark *)child;
- (BOOL)isAncestorOf:(CPBookmark *)other;

@end

// Every bookmark, saved as a property list in Application Support.
@interface CPBookmarkStore : NSObject
{
    CPBookmark *root;
}

+ (CPBookmarkStore *)sharedStore;

- (CPBookmark *)root;
- (void)addBookmarkWithTitle:(NSString *)title URLString:(NSString *)URLString;
- (void)save;
- (void)changed;

// Copies Safari's bookmarks in as a folder. Returns how many bookmarks came
// across, or -1 when there was nothing to import.
- (int)importSafariBookmarks;

@end
