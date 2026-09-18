/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPBookmarks.h"
#import "CPSettings.h"

NSString * const CPBookmarksDidChangeNotification = @"CPBookmarksDidChange";

static NSString * const CPTitleKey    = @"Title";
static NSString * const CPURLKey      = @"URL";
static NSString * const CPChildrenKey = @"Children";

@implementation CPBookmark

+ (CPBookmark *)bookmarkWithTitle:(NSString *)aTitle URLString:(NSString *)aURLString
{
    CPBookmark *bookmark = [[[CPBookmark alloc] init] autorelease];
    [bookmark setTitle:aTitle];
    [bookmark setURLString:aURLString];
    return bookmark;
}

+ (CPBookmark *)folderWithTitle:(NSString *)aTitle
{
    CPBookmark *folder = [[[CPBookmark alloc] init] autorelease];
    [folder setTitle:aTitle];
    folder->children = [[NSMutableArray alloc] init];
    return folder;
}

- (void)dealloc
{
    [title release];
    [URLString release];
    [children release];
    [super dealloc];
}

- (NSString *)title
{
    return (title != nil) ? title : @"";
}

- (void)setTitle:(NSString *)aTitle
{
    if (aTitle == title)
        return;
    [title release];
    title = [aTitle copy];
}

- (NSString *)URLString
{
    return (URLString != nil) ? URLString : @"";
}

- (void)setURLString:(NSString *)aURLString
{
    if (aURLString == URLString)
        return;
    [URLString release];
    URLString = [aURLString copy];
}

- (BOOL)isFolder
{
    return (children != nil);
}

- (NSArray *)children
{
    return children;
}

- (CPBookmark *)parent
{
    return parent;
}

- (void)insertChild:(CPBookmark *)child atIndex:(unsigned)index
{
    if (children == nil || child == nil)
        return;
    if (index > [children count])
        index = [children count];
    [children insertObject:child atIndex:index];
    child->parent = self;
}

- (void)addChild:(CPBookmark *)child
{
    [self insertChild:child atIndex:[children count]];
}

- (void)removeChild:(CPBookmark *)child
{
    if (child->parent == self)
        child->parent = nil;
    [children removeObjectIdenticalTo:child];
}

- (BOOL)isAncestorOf:(CPBookmark *)other
{
    CPBookmark *step;
    for (step = other; step != nil; step = step->parent) {
        if (step == self)
            return YES;
    }
    return NO;
}

@end

static CPBookmark *CPBookmarkFromPropertyList(NSDictionary *plist)
{
    NSArray *children = [plist objectForKey:CPChildrenKey];
    CPBookmark *node;
    unsigned index;

    if (![plist isKindOfClass:[NSDictionary class]])
        return nil;
    if (children == nil)
        return [CPBookmark bookmarkWithTitle:[plist objectForKey:CPTitleKey]
                                   URLString:[plist objectForKey:CPURLKey]];

    node = [CPBookmark folderWithTitle:[plist objectForKey:CPTitleKey]];
    for (index = 0; index < [children count]; index++) {
        CPBookmark *child = CPBookmarkFromPropertyList([children objectAtIndex:index]);
        if (child != nil)
            [node addChild:child];
    }
    return node;
}

static NSDictionary *CPPropertyListFromBookmark(CPBookmark *node)
{
    NSMutableArray *children;
    unsigned index;

    if (![node isFolder])
        return [NSDictionary dictionaryWithObjectsAndKeys:
                [node title], CPTitleKey, [node URLString], CPURLKey, nil];

    children = [NSMutableArray array];
    for (index = 0; index < [[node children] count]; index++)
        [children addObject:CPPropertyListFromBookmark([[node children] objectAtIndex:index])];
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [node title], CPTitleKey, children, CPChildrenKey, nil];
}

// Safari's own format, as found in ~/Library/Safari/Bookmarks.plist on Tiger
// and Leopard. Proxies (the History and Bonjour entries) and Reading List
// have no bookmarks to bring across.
static CPBookmark *CPBookmarkFromSafari(NSDictionary *entry, int *count)
{
    NSString *type = [entry objectForKey:@"WebBookmarkType"];
    NSString *name = [entry objectForKey:@"Title"];
    CPBookmark *folder;
    NSArray *children;
    unsigned index;

    if ([type isEqualToString:@"WebBookmarkTypeLeaf"]) {
        NSString *url = [entry objectForKey:@"URLString"];
        NSString *leafTitle = [[entry objectForKey:@"URIDictionary"] objectForKey:@"title"];
        if ([url length] == 0)
            return nil;
        (*count)++;
        return [CPBookmark bookmarkWithTitle:([leafTitle length] > 0 ? leafTitle : url) URLString:url];
    }
    if (![type isEqualToString:@"WebBookmarkTypeList"] ||
        [name isEqualToString:@"com.apple.ReadingList"])
        return nil;

    if ([name isEqualToString:@"BookmarksBar"])
        name = @"Bookmarks Bar";
    else if ([name isEqualToString:@"BookmarksMenu"])
        name = @"Bookmarks Menu";
    folder = [CPBookmark folderWithTitle:name];
    children = [entry objectForKey:@"Children"];
    for (index = 0; index < [children count]; index++) {
        CPBookmark *child = CPBookmarkFromSafari([children objectAtIndex:index], count);
        if (child != nil)
            [folder addChild:child];
    }
    return folder;
}

@interface CPBookmarkStore (Private)
- (NSString *)path;
@end

@implementation CPBookmarkStore (Private)

- (NSString *)path
{
    return [[[CPSettings sharedSettings] supportDirectory] stringByAppendingPathComponent:@"Bookmarks.plist"];
}

@end

@implementation CPBookmarkStore

+ (CPBookmarkStore *)sharedStore
{
    static CPBookmarkStore *store = nil;
    if (store == nil)
        store = [[CPBookmarkStore alloc] init];
    return store;
}

- (id)init
{
    NSArray *saved;
    unsigned index;

    self = [super init];
    if (self == nil)
        return nil;

    root = [[CPBookmark folderWithTitle:@"Bookmarks"] retain];
    saved = [NSArray arrayWithContentsOfFile:[self path]];
    if (saved == nil) {
        // First run: bring the reader's Safari bookmarks along, since these
        // machines usually have years of them.
        if ([self importSafariBookmarks] < 0)
            [self addBookmarkWithTitle:@"Wikipedia" URLString:@"https://en.wikipedia.org/"];
        [self save];
    } else {
        for (index = 0; index < [saved count]; index++) {
            CPBookmark *node = CPBookmarkFromPropertyList([saved objectAtIndex:index]);
            if (node != nil)
                [root addChild:node];
        }
    }
    return self;
}

- (void)dealloc
{
    [root release];
    [super dealloc];
}

- (CPBookmark *)root
{
    return root;
}

- (void)addBookmarkWithTitle:(NSString *)title URLString:(NSString *)URLString
{
    [root addChild:[CPBookmark bookmarkWithTitle:title URLString:URLString]];
    [self changed];
}

- (void)save
{
    NSMutableArray *plist = [NSMutableArray array];
    unsigned index;

    for (index = 0; index < [[root children] count]; index++)
        [plist addObject:CPPropertyListFromBookmark([[root children] objectAtIndex:index])];
    [plist writeToFile:[self path] atomically:YES];
}

- (void)changed
{
    [self save];
    [[NSNotificationCenter defaultCenter] postNotificationName:CPBookmarksDidChangeNotification object:self];
}

- (int)importSafariBookmarks
{
    NSString *safariPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Safari/Bookmarks.plist"];
    NSDictionary *safari = [NSDictionary dictionaryWithContentsOfFile:safariPath];
    CPBookmark *imported;
    int count = 0;

    if (safari == nil)
        return -1;
    imported = CPBookmarkFromSafari(safari, &count);
    if (imported == nil || count == 0)
        return -1;
    [imported setTitle:@"From Safari"];
    [root addChild:imported];
    [self changed];
    return count;
}

@end
