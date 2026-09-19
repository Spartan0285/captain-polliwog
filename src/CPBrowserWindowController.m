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
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>

#define CPBarHeight     34.0f
#define CPTabBarHeight  22.0f
#define CPStatusHeight  20.0f

static NSString * const CPSearchURLFormat = @"https://lite.duckduckgo.com/lite/?q=%@";

@interface CPBrowserWindowController (Private)
- (NSButton *)addButtonWithImage:(NSImage *)image frame:(NSRect)frame action:(SEL)action toolTip:(NSString *)toolTip;
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
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setBezelStyle:NSTexturedSquareBezelStyle];
    [button setImage:image];
    [button setImagePosition:NSImageOnly];
    [button setTarget:self];
    [button setAction:action];
    [button setToolTip:toolTip];
    [button setAutoresizingMask:NSViewMinYMargin];
    [[[self window] contentView] addSubview:button];
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
    float tabBarTop = height - CPBarHeight - 1.0f;
    NSFont *smallFont = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];

    backButton = [self addButtonWithImage:[CPIcons backImage]
                                    frame:NSMakeRect(8.0f, height - 29.0f, 32.0f, 24.0f)
                                   action:@selector(goBack:)
                                  toolTip:@"Back"];
    forwardButton = [self addButtonWithImage:[CPIcons forwardImage]
                                       frame:NSMakeRect(41.0f, height - 29.0f, 32.0f, 24.0f)
                                      action:@selector(goForward:)
                                     toolTip:@"Forward"];
    reloadButton = [self addButtonWithImage:[CPIcons reloadImage]
                                      frame:NSMakeRect(80.0f, height - 29.0f, 32.0f, 24.0f)
                                     action:@selector(reloadOrStop:)
                                    toolTip:@"Reload"];

    addressField = [[NSTextField alloc] initWithFrame:NSMakeRect(120.0f, height - 28.0f, width - 130.0f, 22.0f)];
    [addressField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [[addressField cell] setScrollable:YES];
    [[addressField cell] setSendsActionOnEndEditing:NO];
    [addressField setTarget:self];
    [addressField setAction:@selector(addressEntered:)];
    [content addSubview:addressField];
    [addressField release];

    [self addSeparatorWithFrame:NSMakeRect(0.0f, tabBarTop, width, 1.0f)
               autoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];

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

    if (isLoading && progress > 0.0) {
        [progressBar setHidden:NO];
        [progressBar setDoubleValue:progress];
    } else {
        [progressBar setHidden:YES];
    }
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
    [window setTitle:@"Captain Polliwog"];
    [window center];

    self = [super initWithWindow:window];
    [window release];
    if (self == nil)
        return nil;

    tabs = [[NSMutableArray alloc] init];
    [window setDelegate:self];
    [self buildInterface];
    return self;
}

- (void)dealloc
{
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
    if (selectedWasLoading && ![tab isLoading] && ![tab isDiscarded]) {
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
    [self loadURL:[CPAppDelegate startPageURL]];
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

- (IBAction)makeTextLarger:(id)sender
{
    [[selectedTab webView] makeTextLarger:sender];
}

- (IBAction)makeTextSmaller:(id)sender
{
    [[selectedTab webView] makeTextSmaller:sender];
}

- (IBAction)newTab:(id)sender
{
    [self addTabWithURL:[CPAppDelegate startPageURL] select:YES];
    [self openLocation:sender];
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
