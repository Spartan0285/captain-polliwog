/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAppDelegate.h"
#import "CPBrowserWindowController.h"
#import "CPCurlProtocol.h"
#import "CPSettings.h"
#import "CPPreferencesController.h"
#import "CPDebugSnapshot.h"
#import "CPTab.h"
#import "CPMemoryWatcher.h"
#import "CPBookmarksController.h"
#import "CPHistory.h"
#import "CPDownloadsController.h"
#import <WebKit/WebKit.h>

static NSMenuItem *CPAddItem(NSMenu *menu, NSString *title, SEL action, NSString *key)
{
    return [menu addItemWithTitle:title action:action keyEquivalent:(key != nil ? key : @"")];
}

static NSMenu *CPAddSubmenu(NSMenu *mainMenu, NSString *title)
{
    NSMenuItem *item = [mainMenu addItemWithTitle:title action:NULL keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    [mainMenu setSubmenu:menu forItem:item];
    [menu release];
    return menu;
}

@implementation CPAppDelegate

+ (NSString *)userAgentApplicationName
{
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *webKitVersion = [[[NSBundle bundleForClass:[WebView class]] infoDictionary] objectForKey:@"CFBundleVersion"];

    // WebKit's bundle version carries an OS prefix digit on Leopard and later
    // ("5534.50.2" is WebKit 534.50.2); Safari's user agent drops it.
    if ([webKitVersion length] > 4 &&
        [[webKitVersion substringToIndex:4] rangeOfString:@"."].location == NSNotFound)
        webKitVersion = [webKitVersion substringFromIndex:1];

    return [NSString stringWithFormat:@"CaptainPolliwog/%@ Safari/%@",
            (appVersion != nil ? appVersion : @"0"),
            (webKitVersion != nil ? webKitVersion : @"523.12")];
}

+ (NSURL *)startPageURL
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"start" ofType:@"html"];
    if (path == nil)
        return [NSURL URLWithString:@"about:blank"];
    return [NSURL fileURLWithPath:path];
}

- (id)init
{
    self = [super init];
    if (self == nil)
        return nil;

    browserWindows = [[NSMutableArray alloc] init];
    // Registered before anything loads, so every https request in the app
    // goes through the bundled OpenSSL instead of the system's ancient one.
    [NSURLProtocol registerClass:[CPCurlProtocol class]];
    return self;
}

- (void)dealloc
{
    [browserWindows release];
    [super dealloc];
}

- (void)buildMainMenu
{
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *item;
    NSMenu *menu;
    NSMenu *historyMenu;

    [NSApp setMainMenu:mainMenu];
    [mainMenu release];

    menu = CPAddSubmenu(mainMenu, @"Captain Polliwog");
    CPAddItem(menu, @"About Captain Polliwog", @selector(orderFrontStandardAboutPanel:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Hide Captain Polliwog", @selector(hide:), @"h");
    item = CPAddItem(menu, @"Hide Others", @selector(hideOtherApplications:), @"h");
    [item setKeyEquivalentModifierMask:(NSCommandKeyMask | NSAlternateKeyMask)];
    CPAddItem(menu, @"Show All", @selector(unhideAllApplications:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Preferences...", @selector(showPreferences:), @",");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Quit Captain Polliwog", @selector(terminate:), @"q");
    // Without a nib, Tiger only treats this as the application menu once told.
    if ([NSApp respondsToSelector:@selector(setAppleMenu:)])
        [NSApp performSelector:@selector(setAppleMenu:) withObject:menu];

    menu = CPAddSubmenu(mainMenu, @"File");
    CPAddItem(menu, @"New Window", @selector(newWindow:), @"n");
    CPAddItem(menu, @"New Tab", @selector(newTab:), @"t");
    CPAddItem(menu, @"Open Location...", @selector(openLocation:), @"l");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Close Tab", @selector(closeCurrentTab:), @"w");
    CPAddItem(menu, @"Close Window", @selector(performClose:), @"W");

    menu = CPAddSubmenu(mainMenu, @"Edit");
    CPAddItem(menu, @"Undo", @selector(undo:), @"z");
    CPAddItem(menu, @"Redo", @selector(redo:), @"Z");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Cut", @selector(cut:), @"x");
    CPAddItem(menu, @"Copy", @selector(copy:), @"c");
    CPAddItem(menu, @"Paste", @selector(paste:), @"v");
    CPAddItem(menu, @"Select All", @selector(selectAll:), @"a");

    menu = CPAddSubmenu(mainMenu, @"View");
    CPAddItem(menu, @"Reload Page", @selector(reload:), @"r");
    CPAddItem(menu, @"Stop", @selector(stopLoading:), @".");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Make Text Bigger", @selector(makeTextLarger:), @"+");
    CPAddItem(menu, @"Make Text Smaller", @selector(makeTextSmaller:), @"-");

    menu = CPAddSubmenu(mainMenu, @"History");
    CPAddItem(menu, @"Back", @selector(goBack:), @"[");
    CPAddItem(menu, @"Forward", @selector(goForward:), @"]");
    CPAddItem(menu, @"Home", @selector(goHome:), @"H");
    historyMenu = menu;

    menu = CPAddSubmenu(mainMenu, @"Bookmarks");
    item = CPAddItem(menu, @"Add Bookmark...", @selector(addBookmark:), @"d");
    [item setTarget:[CPBookmarksController sharedController]];
    item = CPAddItem(menu, @"Edit Bookmarks", @selector(editBookmarks:), @"b");
    [item setKeyEquivalentModifierMask:(NSCommandKeyMask | NSAlternateKeyMask)];
    [item setTarget:[CPBookmarksController sharedController]];
    item = CPAddItem(menu, @"Import Bookmarks from Safari...", @selector(importSafariBookmarks:), nil);
    [item setTarget:[CPBookmarksController sharedController]];
    [menu addItem:[NSMenuItem separatorItem]];
    [[CPBookmarksController sharedController] attachBookmarksMenu:menu historyMenu:historyMenu];

    menu = CPAddSubmenu(mainMenu, @"Window");
    CPAddItem(menu, @"Minimize", @selector(performMiniaturize:), @"m");
    CPAddItem(menu, @"Zoom", @selector(performZoom:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    // Command-Shift-] and [, as in Safari.
    CPAddItem(menu, @"Select Next Tab", @selector(selectNextTab:), @"}");
    CPAddItem(menu, @"Select Previous Tab", @selector(selectPreviousTab:), @"{");
    [menu addItem:[NSMenuItem separatorItem]];
    item = CPAddItem(menu, @"Downloads", @selector(showDownloads:), @"l");
    [item setKeyEquivalentModifierMask:(NSCommandKeyMask | NSAlternateKeyMask)];
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Bring All to Front", @selector(arrangeInFront:), nil);
    [NSApp setWindowsMenu:menu];
}

- (CPBrowserWindowController *)openBrowserWindow
{
    CPBrowserWindowController *controller = [[CPBrowserWindowController alloc] init];
    CPBrowserWindowController *previous = [browserWindows lastObject];

    if (previous != nil) {
        NSRect frame = [[previous window] frame];
        NSPoint topLeft = NSMakePoint(NSMinX(frame), NSMaxY(frame));
        [[controller window] cascadeTopLeftFromPoint:topLeft];
    }

    [browserWindows addObject:controller];
    [controller release];
    return controller;
}

- (void)browserWindowWillClose:(CPBrowserWindowController *)controller
{
    // The controller is still on the stack; let it outlive this call.
    [[controller retain] autorelease];
    [browserWindows removeObject:controller];
}

- (IBAction)showPreferences:(id)sender
{
    [[CPPreferencesController sharedController] showWindow:sender];
}

- (IBAction)newWindow:(id)sender
{
    CPBrowserWindowController *controller = [self openBrowserWindow];
    [controller showWindow:self];
    [controller addTabWithURL:[CPAppDelegate startPageURL] select:YES];
    [controller openLocation:self];
}

// Command-W closes a tab in a browser window; anywhere else (Preferences, an
// About box) it should still just close the window.
- (IBAction)closeCurrentTab:(id)sender
{
    [[NSApp keyWindow] performClose:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(closeCurrentTab:))
        return ([NSApp keyWindow] != nil);
    return YES;
}

// With no window open, Command-T still has to do something useful.
- (IBAction)newTab:(id)sender
{
    [self newWindow:sender];
}

- (void)scheduleLiveTabLimit
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(enforceLiveTabLimit) object:nil];
    [self performSelector:@selector(enforceLiveTabLimit) withObject:nil afterDelay:1.0];
}

// The memory budget covers every tab in every window. The tab showing in each
// window is never discarded, nor one still loading; beyond that, the tabs
// looked at least recently give up their pages first.
- (void)enforceLiveTabLimit
{
    NSMutableArray *candidates = [NSMutableArray array];
    unsigned limit = [[CPSettings sharedSettings] maximumLiveTabs];
    unsigned live = 0;
    unsigned discarded = 0;
    unsigned windowIndex;
    unsigned index;

    for (windowIndex = 0; windowIndex < [browserWindows count]; windowIndex++) {
        CPBrowserWindowController *window = [browserWindows objectAtIndex:windowIndex];
        NSArray *windowTabs = [window tabs];
        for (index = 0; index < [windowTabs count]; index++) {
            CPTab *tab = [windowTabs objectAtIndex:index];
            if ([tab isDiscarded])
                continue;
            live++;
            if (tab != [window selectedTab] && ![tab isLoading])
                [candidates addObject:tab];
        }
    }

    while (live > limit && [candidates count] > 0) {
        CPTab *oldest = [candidates objectAtIndex:0];
        for (index = 1; index < [candidates count]; index++) {
            CPTab *tab = [candidates objectAtIndex:index];
            if ([[tab lastSelected] compare:[oldest lastSelected]] == NSOrderedAscending)
                oldest = tab;
        }
        [oldest discard];
        [candidates removeObject:oldest];
        live--;
        discarded++;
    }

    // Over budget means memory is already tight; discarding a tab leaves the
    // shared WebKit cache untouched, so free that too.
    if (discarded > 0)
        [[CPMemoryWatcher sharedWatcher] relieveMemoryPressure:@"tabs were over the memory budget"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSString *debugURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugURL"];
    NSArray *debugTabs;
    unsigned index;

    [[CPSettings sharedSettings] apply];
    // Before any page loads, so the first visits are recorded too.
    [[CPHistory sharedHistory] start];
    if ([browserWindows count] == 0)
        [self newWindow:self];
    if (debugURL != nil)
        [[browserWindows lastObject] loadAddressString:debugURL];
    // Testing aid: CPDebugTabs, an array of addresses, opens one tab each.
    debugTabs = [[NSUserDefaults standardUserDefaults] arrayForKey:@"CPDebugTabs"];
    for (index = 0; index < [debugTabs count]; index++) {
        [[browserWindows lastObject] addTabWithURL:[NSURL URLWithString:[debugTabs objectAtIndex:index]]
                                            select:YES];
    }
    // Lets the test scripts photograph the bookmark editor and Preferences.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugShowBookmarks"]) {
        [[CPBookmarksController sharedController] editBookmarks:self];
        [[CPBookmarksController sharedController] performSelector:@selector(writeDebugSnapshot)
                                                       withObject:nil
                                                       afterDelay:2.0];
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugShowPreferences"]) {
        [self showPreferences:self];
        [[CPPreferencesController sharedController] performSelector:@selector(writeDebugSnapshot)
                                                         withObject:nil
                                                         afterDelay:2.0];
    }
}

- (IBAction)showDownloads:(id)sender
{
    [[CPDownloadsController sharedController] showWindow:sender];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if (![[CPDownloadsController sharedController] hasActiveDownloads])
        return NSTerminateNow;
    if (NSRunAlertPanel(@"Quit while files are downloading?",
                        @"Downloads in progress will stop, and their partial files will be left as \".download\" files.",
                        @"Quit", @"Cancel", nil) == NSAlertDefaultReturn)
        return NSTerminateNow;
    return NSTerminateCancel;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [[CPHistory sharedHistory] save];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if (!flag)
        [self newWindow:self];
    return YES;
}

@end
