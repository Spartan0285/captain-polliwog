/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPBrowserWindowController.h"
#import "CPAutoFill.h"
#import "CPAppDelegate.h"
#import "CPTab.h"
#import "CPSiteModes.h"
#import "CPTabBarView.h"
#import "CPIcons.h"
#import "CPAddressBar.h"
#import "CPBookmarks.h"
#import "CPBookmarksController.h"
#import "CPDownloadsController.h"
#import "CPDownload.h"
#import "CPSiteSettings.h"
#import "CPSettings.h"
#import "CPDebugSnapshot.h"
#import "CPTitleBarView.h"
#import <WebKit/WebKit.h>

// The single top row: the window's buttons and the toolbar, over the title
// bar and the top of the content view.
#define CPBarHeight     38.0f
#define CPTabBarHeight  22.0f
#define CPStatusHeight  20.0f

static NSString * const CPSearchURLFormat = @"https://lite.duckduckgo.com/lite/?q=%@";

@interface CPBrowserWindowController (Private)
- (NSButton *)addButtonWithImage:(NSImage *)image frame:(NSRect)frame action:(SEL)action toolTip:(NSString *)toolTip;
- (NSButton *)addButtonWithImage:(NSImage *)image frame:(NSRect)frame action:(SEL)action toolTip:(NSString *)toolTip toView:(NSView *)view;
- (NSBox *)addSeparatorWithFrame:(NSRect)frame autoresizingMask:(unsigned int)mask;
- (void)buildInterface;
- (void)showSelectedTab;
- (void)updateChromeForSelectedTab;
- (void)setStatusText:(NSString *)text;
- (void)setAddressFromURL:(NSURL *)url;
- (BOOL)isEditingAddress;
- (NSURL *)URLFromUserInput:(NSString *)input;
- (void)writeDebugSnapshot;
@end

@implementation CPBrowserWindowController (Private)

- (NSButton *)addButtonWithImage:(NSImage *)image frame:(NSRect)frame action:(SEL)action toolTip:(NSString *)toolTip
{
    return [self addButtonWithImage:image frame:frame action:action toolTip:toolTip
                             toView:[[self window] contentView]];
}

- (NSButton *)addButtonWithImage:(NSImage *)image frame:(NSRect)frame action:(SEL)action toolTip:(NSString *)toolTip toView:(NSView *)view
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    // Plain icons, as Safari's toolbar has had since version 7.
    [button setBordered:NO];
    [[button cell] setHighlightsBy:NSContentsCellMask];
    [button setImage:image];
    [button setImagePosition:NSImageOnly];
    [button setTarget:self];
    [button setAction:action];
    [button setToolTip:toolTip];
    [button setAutoresizingMask:NSViewMinYMargin];
    [view addSubview:button];
    [button release];
    return button;
}

- (NSBox *)addSeparatorWithFrame:(NSRect)frame autoresizingMask:(unsigned int)mask
{
    NSBox *box = [[NSBox alloc] initWithFrame:frame];
    [box setBoxType:NSBoxSeparator];
    [box setAutoresizingMask:mask];
    [[[self window] contentView] addSubview:box];
    [box release];
    return box;
}

- (void)buildInterface
{
    NSView *content = [[self window] contentView];
    NSRect bounds = [content bounds];
    float width = NSWidth(bounds);
    float height = NSHeight(bounds);
    NSFont *smallFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    NSView *frameView = [content superview];
    // The standard title bar's height: the bar covers it and this much more.
    float overlap = CPBarHeight - (NSHeight([frameView bounds]) - NSMaxY([content frame]));
    float tabBarTop = height - overlap;
    CPTitleBarView *bar = [CPTitleBarView installInWindow:[self window] height:CPBarHeight];
    float barWidth = NSWidth([bar bounds]);
    float left = [bar windowButtonsMaxX] + 12.0f;
    float buttonY = floorf((CPBarHeight - 24.0f) / 2.0f);

    [(CPUnifiedContentView *)content setOverlap:overlap];

    // Safari's layout, in one row with the window's buttons: back and
    // forward; the address bar with the site's icon, Favorites, page
    // settings and reload inside it; share, downloads and a new tab at the
    // right.
    backButton = [self addButtonWithImage:[CPIcons backImage]
                                    frame:NSMakeRect(left, buttonY, 26.0f, 24.0f)
                                   action:@selector(goBack:)
                                  toolTip:@"Back"
                                   toView:bar];
    forwardButton = [self addButtonWithImage:[CPIcons forwardImage]
                                       frame:NSMakeRect(left + 28.0f, buttonY, 26.0f, 24.0f)
                                      action:@selector(goForward:)
                                     toolTip:@"Forward"
                                      toView:bar];
    newTabButton = [self addButtonWithImage:[CPIcons plusImage]
                                      frame:NSMakeRect(barWidth - 34.0f, buttonY, 26.0f, 24.0f)
                                     action:@selector(newTab:)
                                    toolTip:@"New Tab"
                                     toView:bar];
    downloadsButton = [self addButtonWithImage:[CPIcons downloadsImage]
                                         frame:NSMakeRect(barWidth - 62.0f, buttonY, 26.0f, 24.0f)
                                        action:@selector(showDownloads:)
                                       toolTip:@"Downloads"
                                        toView:bar];
    shareButton = [self addButtonWithImage:[CPIcons shareImage]
                                     frame:NSMakeRect(barWidth - 90.0f, buttonY, 26.0f, 24.0f)
                                    action:@selector(showShareMenu:)
                                   toolTip:@"Share"
                                    toView:bar];
    [backButton setAutoresizingMask:NSViewNotSizable];
    [forwardButton setAutoresizingMask:NSViewNotSizable];
    [newTabButton setAutoresizingMask:NSViewMinXMargin];
    [downloadsButton setAutoresizingMask:NSViewMinXMargin];
    [shareButton setAutoresizingMask:NSViewMinXMargin];

    addressBar = [[CPAddressBar alloc] initWithFrame:NSMakeRect(left + 64.0f, floorf((CPBarHeight - 26.0f) / 2.0f),
                                                                barWidth - (left + 64.0f) - 98.0f, 26.0f)];
    [addressBar setAutoresizingMask:NSViewWidthSizable];
    [bar addSubview:addressBar];
    [addressBar release];
    addressField = [addressBar textField];
    [addressField setTarget:self];
    [addressField setAction:@selector(addressEntered:)];
    reloadButton = [addressBar reloadButton];
    [reloadButton setTarget:self];
    [reloadButton setAction:@selector(reloadOrStop:)];
    [[addressBar favoriteButton] setTarget:self];
    [[addressBar favoriteButton] setAction:@selector(toggleFavorite:)];
    [[addressBar pageButton] setTarget:self];
    [[addressBar pageButton] setAction:@selector(showPageMenu:)];

    tabBar = [[CPTabBarView alloc] initWithFrame:NSMakeRect(0.0f, tabBarTop - CPTabBarHeight,
                                                            width, CPTabBarHeight)];
    [tabBar setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [tabBar setController:self];
    [content addSubview:tabBar];
    [tabBar release];

    pageArea = [[NSView alloc] initWithFrame:NSMakeRect(0.0f, CPStatusHeight + 1.0f, width,
                                                        tabBarTop - CPTabBarHeight - CPStatusHeight - 1.0f)];
    [pageArea setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [content addSubview:pageArea];
    [pageArea release];

    [self addSeparatorWithFrame:NSMakeRect(0.0f, CPStatusHeight, width, 1.0f)
               autoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];

    statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(6.0f, 3.0f, width - 150.0f, 14.0f)];
    [statusField setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [statusField setEditable:NO];
    [statusField setSelectable:NO];
    [statusField setBezeled:NO];
    [statusField setDrawsBackground:NO];
    [statusField setFont:smallFont];
    [[statusField cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [statusField setStringValue:@""];
    [content addSubview:statusField];
    [statusField release];

    progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(width - 136.0f, 4.0f, 128.0f, 12.0f)];
    [progressBar setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
    [progressBar setStyle:NSProgressIndicatorBarStyle];
    [progressBar setControlSize:NSSmallControlSize];
    [progressBar setIndeterminate:NO];
    [progressBar setMinValue:0.0];
    [progressBar setMaxValue:1.0];
    [progressBar setHidden:YES];
    [content addSubview:progressBar];
    [progressBar release];
}

// Swaps the selected tab's page into view. The other tabs' WebViews stay
// alive off-screen until the memory budget says otherwise.
- (void)showSelectedTab
{
    NSArray *shown = [[[pageArea subviews] copy] autorelease];
    WebView *page = [selectedTab webView];
    unsigned index;

    for (index = 0; index < [shown count]; index++) {
        if ([shown objectAtIndex:index] != page)
            [[shown objectAtIndex:index] removeFromSuperview];
    }
    if ([page superview] != pageArea) {
        [page setFrame:[pageArea bounds]];
        [pageArea addSubview:page];
    }
    selectedWasLoading = [selectedTab isLoading];
    [self updateChromeForSelectedTab];
    [tabBar setNeedsDisplay:YES];
}

- (void)updateChromeForSelectedTab
{
    BOOL isLoading = [selectedTab isLoading];
    double progress = [selectedTab progress];

    [[self window] setTitle:(selectedTab != nil ? [selectedTab displayTitle] : @"Captain Polliwog")];
    [self setAddressFromURL:[selectedTab URL]];
    [backButton setEnabled:[selectedTab canGoBack]];
    [forwardButton setEnabled:[selectedTab canGoForward]];
    [reloadButton setImage:(isLoading ? [CPIcons stopImage] : [CPIcons reloadImage])];
    [reloadButton setToolTip:(isLoading ? @"Stop" : @"Reload")];
    [addressBar setIcon:[selectedTab favicon]];
    [addressBar setProgress:(isLoading ? MAX(progress, 0.08) : 0.0)];
    {
        NSURL *url = [selectedTab URL];
        BOOL web = [CPSiteSettings siteNameForURL:url] != nil;
        BOOL favorite = web && [[CPBookmarkStore sharedStore] isFavoriteURLString:[url absoluteString]];
        [[addressBar favoriteButton] setImage:(favorite ? [CPIcons filledStarImage] : [CPIcons starImage])];
        [[addressBar favoriteButton] setToolTip:(favorite ? @"Remove from Favorites" : @"Add to Favorites")];
        [[addressBar favoriteButton] setEnabled:web];
        [[addressBar pageButton] setEnabled:web];
        [shareButton setEnabled:web];
    }
    [progressBar setHidden:YES];
}

// Mouse-over fires constantly; only redraw the status bar when the text changes.
- (void)setStatusText:(NSString *)text
{
    if (text == nil)
        text = @"";
    if (![[statusField stringValue] isEqualToString:text])
        [statusField setStringValue:text];
}

- (void)setAddressFromURL:(NSURL *)url
{
    NSString *text;

    if ([self isEditingAddress])
        return;
    if (url == nil || [url isEqual:[CPAppDelegate startPageURL]])
        text = @"";
    else
        text = [url absoluteString];
    if (![[addressField stringValue] isEqualToString:text])
        [addressField setStringValue:text];
}

- (BOOL)isEditingAddress
{
    id responder = [[self window] firstResponder];
    return [responder isKindOfClass:[NSTextView class]] &&
           [(NSTextView *)responder delegate] == (id)addressField;
}

- (NSURL *)URLFromUserInput:(NSString *)input
{
    NSString *text = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *query;
    NSURL *url = nil;

    if ([text length] == 0)
        return nil;

    if ([text rangeOfString:@" "].location == NSNotFound) {
        if ([text rangeOfString:@"://"].location != NSNotFound ||
            [text hasPrefix:@"about:"] || [text hasPrefix:@"file:"] || [text hasPrefix:@"data:"])
            url = [NSURL URLWithString:text];
        else if ([text rangeOfString:@"."].location != NSNotFound || [text hasPrefix:@"localhost"])
            url = [NSURL URLWithString:[@"http://" stringByAppendingString:text]];
        if (url != nil)
            return url;
    }

    query = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)text, NULL,
                                                                CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                kCFStringEncodingUTF8);
    url = [NSURL URLWithString:[NSString stringWithFormat:CPSearchURLFormat, query]];
    [query release];
    return url;
}

- (void)writeDebugSnapshot
{
    // When the scripts are photographing another window, stay out of the way.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugShowPreferences"] ||
        [[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugShowBookmarks"])
        return;
    // CPDebugAutoFill: AutoFill the page's form first (addresses only need
    // no password).
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugAutoFill"] && ![selectedTab isDiscarded])
        [CPAutoFill fillFormInTab:selectedTab];
    CPWriteWindowSnapshot([self window]);

    // CPDebugScript: JavaScript to run in the page, its result logged, for
    // looking inside pages the test scripts load.
    {
        NSString *script = [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugScript"];
        if (script != nil && ![selectedTab isDiscarded]) {
            NSString *result = [[selectedTab webView] stringByEvaluatingJavaScriptFromString:script];
            NSLog(@"Captain Polliwog: script result: %@", result);
        }
    }
}

@end

@implementation CPBrowserWindowController

- (id)init
{
    NSRect visible = [[NSScreen mainScreen] visibleFrame];
    NSRect contentRect = NSMakeRect(0.0f, 0.0f,
                                    MIN(1000.0f, NSWidth(visible) - 40.0f),
                                    MIN(760.0f, NSHeight(visible) - 60.0f));
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                                                              NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [window setReleasedWhenClosed:NO];
    [window setMinSize:NSMakeSize(420.0f, 300.0f)];
    {
        // Leaves the band under the single top row to CPTitleBarView.
        CPUnifiedContentView *content = [[CPUnifiedContentView alloc] initWithFrame:[[window contentView] frame]];
        [window setContentView:content];
        [content release];
    }
    [window setTitle:@"Captain Polliwog"];
    [window center];

    self = [super initWithWindow:window];
    [window release];
    if (self == nil)
        return nil;

    tabs = [[NSMutableArray alloc] init];
    [window setDelegate:self];
    [self buildInterface];
    downloadsProgressStep = -2;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadsChanged:)
                                                 name:CPDownloadDidChangeNotification object:nil];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [tabs release];
    [super dealloc];
}

- (NSArray *)tabs
{
    return tabs;
}

- (CPTab *)selectedTab
{
    return selectedTab;
}

- (CPTab *)addTabWithURL:(NSURL *)url select:(BOOL)select
{
    CPTab *tab = [[CPTab alloc] initWithOwner:self];
    unsigned position = [tabs count];

    // New tabs go just after the current one, as in Safari.
    if (selectedTab != nil)
        position = [tabs indexOfObject:selectedTab] + 1;
    [tabs insertObject:tab atIndex:position];
    [tab release];

    if (url != nil)
        [tab loadURL:url];
    if (select || selectedTab == nil)
        [self selectTab:tab];
    else
        [tabBar setNeedsDisplay:YES];

    [(CPAppDelegate *)[NSApp delegate] enforceLiveTabLimit];
    return tab;
}

- (void)selectTab:(CPTab *)tab
{
    if (tab == nil || ![tabs containsObject:tab])
        return;
    selectedTab = tab;
    [tab noteSelected];
    // Focus goes to the page, ending any half-typed address, as in Safari;
    // New Tab puts it back in the address field straight afterwards.
    [[self window] makeFirstResponder:[tab webView]];
    [self showSelectedTab];
    [(CPAppDelegate *)[NSApp delegate] enforceLiveTabLimit];
}

- (void)closeTab:(CPTab *)tab
{
    unsigned index = [tabs indexOfObject:tab];

    if (index == NSNotFound)
        return;
    if ([tabs count] == 1) {
        [[self window] performClose:self];
        return;
    }

    [[tab retain] autorelease];
    [tab close];
    [tabs removeObjectAtIndex:index];
    if (tab == selectedTab) {
        selectedTab = nil;
        [self selectTab:[tabs objectAtIndex:(index < [tabs count] ? index : [tabs count] - 1)]];
    } else {
        [tabBar setNeedsDisplay:YES];
    }
}

- (void)loadURL:(NSURL *)url
{
    if (url == nil)
        return;
    if (selectedTab == nil) {
        [self addTabWithURL:url select:YES];
        return;
    }
    // Leave the address field so it can show where we are going.
    if ([self isEditingAddress])
        [[self window] makeFirstResponder:[selectedTab webView]];
    [selectedTab loadURL:url];
    [self showSelectedTab];
}

- (void)loadAddressString:(NSString *)address
{
    [self loadURL:[self URLFromUserInput:address]];
}

#pragma mark CPTab owner

- (void)tabDidChange:(CPTab *)tab
{
    [tabBar setNeedsDisplay:YES];
    // A background tab that has just finished loading becomes eligible to be
    // discarded. Deferred: its WebView is still on the stack right now.
    if (![tab isLoading] && ![tab isDiscarded])
        [(CPAppDelegate *)[NSApp delegate] scheduleLiveTabLimit];
    if (tab != selectedTab)
        return;
    [self updateChromeForSelectedTab];

    // The test scripts photograph the window once the selected page is in.
    if (selectedWasLoading && ![tab isLoading] && ![tab isDiscarded] && ![[tab URL] isEqual:[CPAppDelegate startPageURL]]) {
        if (CPDebugSnapshotPath() != nil) {
            // CPDebugReader: photograph the page's Reader version instead.
            static BOOL switchedToReader = NO;
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugReader"] && !switchedToReader) {
                switchedToReader = YES;
                NSLog(@"Captain Polliwog: finished %@, switching to Reader", [tab URL]);
                // Not from inside the load that just finished.
                [tab performSelector:@selector(toggleReader) withObject:nil afterDelay:0.5];
                selectedWasLoading = YES;
                return;
            }
            NSLog(@"Captain Polliwog: finished %@", [tab URL]);
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(writeDebugSnapshot) object:nil];
            [self performSelector:@selector(writeDebugSnapshot) withObject:nil afterDelay:2.0];
        }
    }
    // Loading again (a cancelled load gives way to the next): not yet.
    if ([tab isLoading] && CPDebugSnapshotPath() != nil)
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(writeDebugSnapshot) object:nil];
    selectedWasLoading = [tab isLoading];
}

- (void)tab:(CPTab *)tab showStatusText:(NSString *)text
{
    if (tab == selectedTab)
        [self setStatusText:text];
}

- (CPTab *)tab:(CPTab *)tab openTabWithRequest:(NSURLRequest *)request inBackground:(BOOL)background
{
    CPTab *opened = [self addTabWithURL:nil select:!background];
    if (request != nil)
        [opened loadRequest:request];
    return opened;
}

- (void)tabWantsToClose:(CPTab *)tab
{
    [self closeTab:tab];
}

#pragma mark CPTabBarView data source

- (NSArray *)tabsForTabBar
{
    return tabs;
}

- (CPTab *)selectedTabForTabBar
{
    return selectedTab;
}

- (void)tabBarSelectTab:(CPTab *)tab
{
    [self selectTab:tab];
}

- (void)tabBarCloseTab:(CPTab *)tab
{
    [self closeTab:tab];
}

- (void)tabBarNewTab
{
    [self newTab:self];
}

#pragma mark Actions

- (IBAction)goBack:(id)sender
{
    [selectedTab goBack];
}

- (IBAction)goForward:(id)sender
{
    [selectedTab goForward];
}

- (IBAction)goHome:(id)sender
{
    [self loadURL:[CPAppDelegate homePageURL]];
}

- (IBAction)reload:(id)sender
{
    [selectedTab reload];
    [self showSelectedTab];
}

- (IBAction)stopLoading:(id)sender
{
    [selectedTab stopLoading];
}

- (IBAction)reloadOrStop:(id)sender
{
    if ([selectedTab isLoading])
        [self stopLoading:sender];
    else
        [self reload:sender];
}

- (IBAction)openLocation:(id)sender
{
    [[self window] makeFirstResponder:addressField];
    [addressField selectText:sender];
}

- (IBAction)addressEntered:(id)sender
{
    NSString *address = [addressField stringValue];
    if ([[address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0)
        return;
    [[self window] makeFirstResponder:[selectedTab webView]];
    [self loadAddressString:address];
}

// View > Site Version: tags are CPSiteMode values; -1 is "use the default".
- (IBAction)setSiteMode:(id)sender
{
    NSURL *page = [selectedTab URL];
    int mode = [sender tag];

    if (![CPSiteModes appliesToURL:page])
        return;
    if (mode < 0)
        [CPSiteModes removeModeForURL:page];
    else
        [CPSiteModes setMode:(CPSiteMode)mode forURL:page];
    [selectedTab reloadForSiteMode];
}

- (IBAction)autoFillForm:(id)sender
{
    [CPAutoFill fillFormInTab:[self selectedTab]];
}

- (IBAction)toggleReader:(id)sender
{
    [[self selectedTab] toggleReader];
    [self updateChromeForSelectedTab];
}

// Text size steps, kept for each site.
static float CPTextSizes[] = { 0.7f, 0.8f, 0.9f, 1.0f, 1.1f, 1.2f, 1.35f, 1.5f, 1.75f, 2.0f };
#define CPTextSizeCount (sizeof(CPTextSizes) / sizeof(CPTextSizes[0]))

- (void)stepTextSize:(int)direction
{
    NSURL *url = [selectedTab URL];
    float size = [CPSiteSettings siteNameForURL:url] != nil ? [CPSiteSettings textSizeForURL:url] : [[selectedTab webView] textSizeMultiplier];
    unsigned i, index = 3;
    for (i = 0; i < CPTextSizeCount; i++) {
        if (CPTextSizes[i] <= size + 0.01f)
            index = i;
    }
    if (direction > 0 && index + 1 < CPTextSizeCount)
        index++;
    else if (direction < 0 && index > 0)
        index--;
    else if (direction == 0)
        index = 3;
    if ([CPSiteSettings siteNameForURL:url] != nil)
        [CPSiteSettings setTextSize:CPTextSizes[index] forURL:url];
    [[selectedTab webView] setTextSizeMultiplier:CPTextSizes[index]];
}

- (IBAction)makeTextLarger:(id)sender
{
    [self stepTextSize:1];
}

- (IBAction)makeTextSmaller:(id)sender
{
    [self stepTextSize:-1];
}

- (IBAction)actualSize:(id)sender
{
    [self stepTextSize:0];
}

- (IBAction)newTab:(id)sender
{
    CPNewTabPage page = [[CPSettings sharedSettings] newTabPage];
    NSURL *url = page == CPNewTabShowsHomePage ? [CPAppDelegate homePageURL]
        : page == CPNewTabShowsBlankPage ? [NSURL URLWithString:@"about:blank"] : [CPAppDelegate startPageURL];
    [self addTabWithURL:url select:YES];
    [self openLocation:sender];
}

- (IBAction)toggleFavorite:(id)sender
{
    NSURL *url = [selectedTab URL];
    CPBookmarkStore *store = [CPBookmarkStore sharedStore];
    if ([CPSiteSettings siteNameForURL:url] == nil)
        return;
    if ([store isFavoriteURLString:[url absoluteString]])
        [store removeFavoriteURLString:[url absoluteString]];
    else
        [store addFavoriteWithTitle:[selectedTab displayTitle] URLString:[url absoluteString]];
    [self updateChromeForSelectedTab];
}

- (void)popUpMenu:(NSMenu *)menu fromButton:(NSButton *)button
{
    NSEvent *event = [NSEvent mouseEventWithType:NSLeftMouseDown
                                        location:[button convertPoint:NSMakePoint(0.0f, -2.0f) toView:nil]
                                   modifierFlags:0 timestamp:[[NSApp currentEvent] timestamp]
                                    windowNumber:[[self window] windowNumber] context:nil
                                     eventNumber:0 clickCount:1 pressure:1.0f];
    [NSMenu popUpContextMenu:menu withEvent:event forView:button];
}

static NSMenuItem *CPMenuItem(NSMenu *menu, NSString *title, SEL action, id target, int state)
{
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
    [item setTarget:target];
    [item setState:state];
    return item;
}

// The downloads button shows how far the running downloads have got, as
// Safari's does. Redrawn only when it moves a twentieth.
- (void)downloadsChanged:(NSNotification *)notification
{
    double progress = [[CPDownloadsController sharedController] overallProgress];
    int step = progress < -1.5 ? -2 : progress < 0.0 ? -1 : (int)(progress * 20.0);
    if (step == downloadsProgressStep)
        return;
    downloadsProgressStep = step;
    [downloadsButton setImage:(step == -2 ? [CPIcons downloadsImage] : [CPIcons downloadsImageWithProgress:progress])];
}

- (IBAction)showShareMenu:(id)sender
{
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Share"] autorelease];
    CPMenuItem(menu, @"Email This Page", @selector(emailPage:), self, NSOffState);
    CPMenuItem(menu, @"Copy Link", @selector(copyLink:), self, NSOffState);
    CPMenuItem(menu, @"Copy Title and Link", @selector(copyTitleAndLink:), self, NSOffState);
    [menu addItem:[NSMenuItem separatorItem]];
    CPMenuItem(menu, @"Add to Favorites", @selector(toggleFavorite:), self,
               [[CPBookmarkStore sharedStore] isFavoriteURLString:[[selectedTab URL] absoluteString]] ? NSOnState : NSOffState);
    CPMenuItem(menu, @"Add Bookmark...", @selector(addBookmark:), [CPBookmarksController sharedController], NSOffState);
    [menu addItem:[NSMenuItem separatorItem]];
    if ([selectedTab isShowingPDF]) {
        CPMenuItem(menu, @"Open in Preview", @selector(openPDFInPreview:), self, NSOffState);
        CPMenuItem(menu, @"Save PDF...", @selector(savePDF:), self, NSOffState);
    }
    CPMenuItem(menu, @"Open in Safari", @selector(openInSafari:), self, NSOffState);
    [self popUpMenu:menu fromButton:shareButton];
}

- (NSString *)PDFFilename
{
    NSString *name = [[[[selectedTab URL] path] lastPathComponent] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if ([name length] < 2)
        name = @"document";
    if (![[[name pathExtension] lowercaseString] isEqualToString:@"pdf"])
        name = [name stringByAppendingPathExtension:@"pdf"];
    return name;
}

- (void)openPDFInPreview:(id)sender
{
    // The bytes already here, not a second trip over the network.
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Captain Polliwog PDFs"];
    NSString *path = [folder stringByAppendingPathComponent:[self PDFFilename]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder attributes:nil];
    if (![[selectedTab pageData] writeToFile:path atomically:YES] ||
        ![[NSWorkspace sharedWorkspace] openFile:path withApplication:@"Preview"])
        NSBeep();
}

- (void)savePDF:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setRequiredFileType:@"pdf"];
    [panel beginSheetForDirectory:[[CPSettings sharedSettings] downloadsFolder] file:[self PDFFilename]
                   modalForWindow:[self window] modalDelegate:self
                   didEndSelector:@selector(savePDFPanelDidEnd:returnCode:contextInfo:) contextInfo:[[selectedTab pageData] retain]];
}

- (void)savePDFPanelDidEnd:(NSSavePanel *)panel returnCode:(int)code contextInfo:(void *)context
{
    NSData *data = [(NSData *)context autorelease];
    if (code == NSOKButton && ![data writeToFile:[panel filename] atomically:YES])
        NSBeep();
}

- (void)emailPage:(id)sender
{
    NSURL *url = [selectedTab URL];
    NSString *subject = [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[selectedTab displayTitle], NULL,
                          CFSTR("&=?+#%"), kCFStringEncodingUTF8) autorelease];
    NSString *body = [(NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)[url absoluteString], NULL,
                       CFSTR("&=?+#%"), kCFStringEncodingUTF8) autorelease];
    // Mail, or whatever the Mac uses for email.
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"mailto:?subject=%@&body=%@", subject, body]]];
}

- (void)copyLink:(id)sender
{
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    NSURL *url = [selectedTab URL];
    [board declareTypes:[NSArray arrayWithObjects:NSURLPboardType, NSStringPboardType, nil] owner:nil];
    [url writeToPasteboard:board];
    [board setString:[url absoluteString] forType:NSStringPboardType];
}

- (void)copyTitleAndLink:(id)sender
{
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    [board declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [board setString:[NSString stringWithFormat:@"%@\n%@", [selectedTab displayTitle], [[selectedTab URL] absoluteString]]
             forType:NSStringPboardType];
}

- (void)openInSafari:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:[selectedTab URL]]
                    withAppBundleIdentifier:@"com.apple.Safari" options:NSWorkspaceLaunchDefault
             additionalEventParamDescriptor:nil launchIdentifiers:NULL];
}

- (IBAction)showPageMenu:(id)sender
{
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Page"] autorelease];
    NSURL *url = [selectedTab URL];
    NSString *site = [CPSiteSettings siteNameForURL:url];
    NSMenuItem *item;
    int mode;

    if (site == nil)
        return;
    CPMenuItem(menu, @"Make Text Bigger", @selector(makeTextLarger:), self, NSOffState);
    CPMenuItem(menu, @"Make Text Smaller", @selector(makeTextSmaller:), self, NSOffState);
    CPMenuItem(menu, [NSString stringWithFormat:@"Actual Size (now %.0f%%)", [CPSiteSettings textSizeForURL:url] * 100.0f],
               @selector(actualSize:), self, NSOffState);
    [menu addItem:[NSMenuItem separatorItem]];
    CPMenuItem(menu, ([selectedTab isShowingReader] ? @"Hide Reader" : @"Show Reader"), @selector(toggleReader:), self, NSOffState);
    CPMenuItem(menu, [NSString stringWithFormat:@"Always Use Reader on %@", site], @selector(toggleReaderForSite:), self,
               [CPSiteSettings usesReaderForURL:url] ? NSOnState : NSOffState);
    [menu addItem:[NSMenuItem separatorItem]];
    mode = [CPSiteModes hasModeForURL:url] ? (int)[CPSiteModes modeForURL:url] : -1;
    item = CPMenuItem(menu, @"Desktop Version", @selector(setSiteMode:), self, mode == CPSiteModeDesktop ? NSOnState : NSOffState);
    [item setTag:CPSiteModeDesktop];
    item = CPMenuItem(menu, @"Mobile Version", @selector(setSiteMode:), self, mode == CPSiteModeMobile ? NSOnState : NSOffState);
    [item setTag:CPSiteModeMobile];
    item = CPMenuItem(menu, @"Basic Version", @selector(setSiteMode:), self, mode == CPSiteModeBasic ? NSOnState : NSOffState);
    [item setTag:CPSiteModeBasic];
    item = CPMenuItem(menu, [NSString stringWithFormat:@"Default Version (%@)", [CPSiteModes nameForMode:[CPSiteModes defaultModeForURL:url]]],
                      @selector(setSiteMode:), self, mode < 0 ? NSOnState : NSOffState);
    [item setTag:-1];
    [menu addItem:[NSMenuItem separatorItem]];
    CPMenuItem(menu, [NSString stringWithFormat:@"JavaScript on %@", site], @selector(toggleJavaScriptForSite:), self,
               [CPSiteSettings javaScriptEnabledForURL:url] ? NSOnState : NSOffState);
    CPMenuItem(menu, [NSString stringWithFormat:@"Images on %@", site], @selector(toggleImagesForSite:), self,
               [CPSiteSettings imagesEnabledForURL:url] ? NSOnState : NSOffState);
    [self popUpMenu:menu fromButton:[addressBar pageButton]];
}

- (IBAction)toggleReaderForSite:(id)sender
{
    NSURL *url = [selectedTab URL];
    BOOL uses = ![CPSiteSettings usesReaderForURL:url];
    [CPSiteSettings setUsesReader:uses forURL:url];
    if (uses != [selectedTab isShowingReader])
        [self toggleReader:sender];
}

- (IBAction)toggleJavaScriptForSite:(id)sender
{
    NSURL *url = [selectedTab URL];
    [CPSiteSettings setJavaScriptEnabled:![CPSiteSettings javaScriptEnabledForURL:url] forURL:url];
    [selectedTab applySiteSettings];
    [selectedTab reload];
}

- (IBAction)toggleImagesForSite:(id)sender
{
    NSURL *url = [selectedTab URL];
    [CPSiteSettings setImagesEnabled:![CPSiteSettings imagesEnabledForURL:url] forURL:url];
    [selectedTab applySiteSettings];
    [selectedTab reload];
}

- (IBAction)showDownloads:(id)sender
{
    [[CPDownloadsController sharedController] showWindow:sender];
}

- (IBAction)closeCurrentTab:(id)sender
{
    if (selectedTab != nil)
        [self closeTab:selectedTab];
}

- (IBAction)selectNextTab:(id)sender
{
    unsigned index = [tabs indexOfObject:selectedTab];
    if ([tabs count] > 1 && index != NSNotFound)
        [self selectTab:[tabs objectAtIndex:(index + 1) % [tabs count]]];
}

- (IBAction)selectPreviousTab:(id)sender
{
    unsigned index = [tabs indexOfObject:selectedTab];
    if ([tabs count] > 1 && index != NSNotFound)
        [self selectTab:[tabs objectAtIndex:(index + [tabs count] - 1) % [tabs count]]];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL action = [item action];
    WebView *page = [selectedTab isDiscarded] ? nil : [selectedTab webView];

    if (action == @selector(goBack:))
        return [selectedTab canGoBack];
    if (action == @selector(goForward:))
        return [selectedTab canGoForward];
    if (action == @selector(stopLoading:))
        return [selectedTab isLoading];
    if (action == @selector(makeTextLarger:))
        return (page != nil && [page canMakeTextLarger]);
    if (action == @selector(makeTextSmaller:))
        return (page != nil && [page canMakeTextSmaller]);
    if (action == @selector(selectNextTab:) || action == @selector(selectPreviousTab:))
        return ([tabs count] > 1);
    if (action == @selector(autoFillForm:))
        return page != nil;
    if (action == @selector(toggleReader:)) {
        [item setState:[selectedTab isShowingReader] ? NSOnState : NSOffState];
        return [selectedTab isShowingReader] || [selectedTab canShowReader];
    }
    if (action == @selector(setSiteMode:)) {
        NSURL *site = [selectedTab URL];
        BOOL applies = [CPSiteModes appliesToURL:site];
        BOOL own = applies && [CPSiteModes hasModeForURL:site];
        if ([item tag] < 0) {
            [item setTitle:[NSString stringWithFormat:@"Use Default (%@)",
                            [CPSiteModes nameForMode:[CPSiteModes defaultModeForURL:site]]]];
            [item setState:(applies && !own) ? NSOnState : NSOffState];
        } else {
            [item setState:(own && (int)[CPSiteModes modeForURL:site] == [item tag]) ? NSOnState : NSOffState];
        }
        return applies;
    }
    return YES;
}

#pragma mark NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification
{
    unsigned index;

    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    for (index = 0; index < [tabs count]; index++)
        [[tabs objectAtIndex:index] close];
    [tabs removeAllObjects];
    selectedTab = nil;
    [(CPAppDelegate *)[NSApp delegate] browserWindowWillClose:self];
}

@end
