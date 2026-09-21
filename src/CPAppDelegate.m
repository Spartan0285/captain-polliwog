/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAppDelegate.h"
#import "CPSiteModes.h"
#import "CPMediaRelay.h"
#import "CPAccelerator.h"
#import "CPBrowserWindowController.h"
#import "CPCurlProtocol.h"
#import "CPSettings.h"
#import "CPPreferencesController.h"
#import "CPAutoFillController.h"
#import "CPDebugSnapshot.h"
#import "CPTab.h"
#import "CPMemoryWatcher.h"
#import "CPBookmarksController.h"
#import "CPHistory.h"
#import "CPDownloadsController.h"
#import "CPPrivateBrowsing.h"
#import "CPUpdater.h"
#import "CPDefaultBrowser.h"
#import "CPSafeBrowsing.h"
#import "CPAbout.h"
#import "CPFeedback.h"
#import "CPWelcome.h"
#import "CPUpdateController.h"
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

+ (NSURL *)homePageURL
{
    NSString *home = [[CPSettings sharedSettings] homePage];
    NSURL *url = [home length] ? [NSURL URLWithString:home] : nil;
    return ([[url scheme] length] && [[url host] length]) ? url : [self startPageURL];
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
    CPAddItem(menu, @"About Captain Polliwog", @selector(showAbout:), nil);
    CPAddItem(menu, @"Check for Updates...", @selector(checkForUpdates:), nil);
    // Next to About, where someone annoyed enough to write is already
    // looking for a name to complain to.
    CPAddItem(menu, @"Send Feedback...", @selector(sendFeedback:), nil);
    CPAddItem(menu, @"Welcome Aboard...", @selector(showWelcome:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Private Browsing", @selector(togglePrivateBrowsing:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Hide Captain Polliwog", @selector(hide:), @"h");
    item = CPAddItem(menu, @"Hide Others", @selector(hideOtherApplications:), @"h");
    [item setKeyEquivalentModifierMask:(NSCommandKeyMask | NSAlternateKeyMask)];
    CPAddItem(menu, @"Show All", @selector(unhideAllApplications:), nil);
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Preferences...", @selector(showPreferences:), @",");
    CPAddItem(menu, @"AutoFill...", @selector(showAutoFill:), nil);
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
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Save As...", @selector(savePageAs:), @"S");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Print...", @selector(printPage:), @"p");

    menu = CPAddSubmenu(mainMenu, @"Edit");
    CPAddItem(menu, @"Undo", @selector(undo:), @"z");
    CPAddItem(menu, @"Redo", @selector(redo:), @"Z");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Cut", @selector(cut:), @"x");
    CPAddItem(menu, @"Copy", @selector(copy:), @"c");
    CPAddItem(menu, @"Paste", @selector(paste:), @"v");
    CPAddItem(menu, @"Select All", @selector(selectAll:), @"a");
    [menu addItem:[NSMenuItem separatorItem]];
    {
        NSMenuItem *findItem = [menu addItemWithTitle:@"Find" action:NULL keyEquivalent:@""];
        NSMenu *findMenu = [[[NSMenu alloc] initWithTitle:@"Find"] autorelease];
        CPAddItem(findMenu, @"Find...", @selector(showFindBar:), @"f");
        CPAddItem(findMenu, @"Find Next", @selector(findNext:), @"g");
        CPAddItem(findMenu, @"Find Previous", @selector(findPrevious:), @"G");
        CPAddItem(findMenu, @"Hide Find Banner", @selector(hideFindBar:), nil);
        [findMenu addItem:[NSMenuItem separatorItem]];
        CPAddItem(findMenu, @"Use Selection for Find", @selector(useSelectionForFind:), @"e");
        [menu setSubmenu:findMenu forItem:findItem];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"AutoFill Form", @selector(autoFillForm:), @"A");

    menu = CPAddSubmenu(mainMenu, @"View");
    {
        // Safari's key for the same thing.
        NSMenuItem *overview = CPAddItem(menu, @"Show All Tabs", @selector(toggleTabOverview:), @"\\");
        [overview setKeyEquivalentModifierMask:(NSCommandKeyMask | NSShiftKeyMask)];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Reload Page", @selector(reload:), @"r");
    CPAddItem(menu, @"Stop", @selector(stopLoading:), @".");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Make Text Bigger", @selector(makeTextLarger:), @"+");
    CPAddItem(menu, @"Make Text Smaller", @selector(makeTextSmaller:), @"-");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Reader", @selector(toggleReader:), @"R");
    // Retitled in validateMenuItem: to name the player that will be used.
    CPAddItem(menu, @"Play Video in Media Player", @selector(playVideoExternally:), @"E");
    {
        // Which version of the current site to ask for; see CPSiteModes.
        NSMenuItem *siteItem = [menu addItemWithTitle:@"Site Version" action:NULL keyEquivalent:@""];
        NSMenu *siteMenu = [[[NSMenu alloc] initWithTitle:@"Site Version"] autorelease];
        [CPAddItem(siteMenu, @"Desktop", @selector(setSiteMode:), nil) setTag:CPSiteModeDesktop];
        [CPAddItem(siteMenu, @"Mobile", @selector(setSiteMode:), nil) setTag:CPSiteModeMobile];
        [CPAddItem(siteMenu, @"Basic", @selector(setSiteMode:), nil) setTag:CPSiteModeBasic];
        [siteMenu addItem:[NSMenuItem separatorItem]];
        [CPAddItem(siteMenu, @"Use Default", @selector(setSiteMode:), nil) setTag:-1];
        [menu setSubmenu:siteMenu forItem:siteItem];
    }

    menu = CPAddSubmenu(mainMenu, @"History");
    CPAddItem(menu, @"Back", @selector(goBack:), @"[");
    CPAddItem(menu, @"Forward", @selector(goForward:), @"]");
    CPAddItem(menu, @"Home", @selector(goHome:), @"H");
    [menu addItem:[NSMenuItem separatorItem]];
    CPAddItem(menu, @"Reopen Last Closed Tab", @selector(reopenClosedTab:), @"T");
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

- (IBAction)showAutoFill:(id)sender
{
    [[CPAutoFillController sharedController] showWindow:sender];
}

- (IBAction)showPreferences:(id)sender
{
    [[CPPreferencesController sharedController] showWindow:sender];
}

- (IBAction)showAbout:(id)sender
{
    [CPAbout show];
}

- (IBAction)showWelcome:(id)sender
{
    [CPWelcome show];
}

- (IBAction)sendFeedback:(id)sender
{
    // The window it will offer a picture of, and the address that names
    // where they were: for a browser that is the page, which is also the
    // single most useful thing in the report.
    CPBrowserWindowController *controller = [browserWindows lastObject];
    NSURL *url = controller != nil ? [[controller selectedTab] URL] : nil;

    [CPFeedback openForWindow:(controller != nil ? [controller window] : nil)
                         page:(url != nil ? [url absoluteString] : @"")];
}

- (IBAction)checkForUpdates:(id)sender
{
    [[CPUpdateController sharedController] checkAsked:sender];
}

- (IBAction)newWindow:(id)sender
{
    CPBrowserWindowController *controller = [self openBrowserWindow];
    [controller showWindow:self];
    [controller addTabWithURL:[CPAppDelegate homePageURL] select:YES];
    [controller openLocation:self];
}

// Command-W closes a tab in a browser window; anywhere else (Preferences, an
// About box) it should still just close the window.
- (IBAction)closeCurrentTab:(id)sender
{
    [[NSApp keyWindow] performClose:sender];
}

- (IBAction)togglePrivateBrowsing:(id)sender
{
    CPPrivateBrowsing *privacy = [CPPrivateBrowsing sharedPrivateBrowsing];

    if ([privacy isEnabled]) {
        [privacy setEnabled:NO];
        return;
    }
    if (NSRunAlertPanel(@"Turn on private browsing?",
                        @"While it is on, pages are not added to History, nothing is saved to the "
                        @"disk cache, and cookies set by sites are removed when you turn it off or quit. "
                        @"Sites can still see cookies you already had.",
                        @"Turn On", @"Cancel", nil) == NSAlertDefaultReturn)
        [privacy setEnabled:YES];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(togglePrivateBrowsing:)) {
        [item setState:([[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled] ? NSOnState : NSOffState)];
        return YES;
    }
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

// Debugging: once a minute, what WebKit holds -- the JavaScript heap, live
// objects by type, global objects (one per frame), cached pages and fonts --
// to tell a leak in a page from one in the engine or the app.
static size_t CPStatisticCount(Class statistics, NSString *name)
{
    SEL selector = NSSelectorFromString(name);
    if (![statistics respondsToSelector:selector])
        return 0;
    return ((size_t (*)(id, SEL))[statistics methodForSelector:selector])(statistics, selector);
}

- (void)logMemoryStatistics:(NSTimer *)timer
{
    Class statistics = NSClassFromString(@"WebCoreStatistics");
    NSMutableArray *types = [NSMutableArray array];
    NSCountedSet *counts;
    NSEnumerator *names;
    NSString *name;

    if (statistics == Nil)
        return;
    counts = [statistics respondsToSelector:@selector(javaScriptObjectTypeCounts)] ? [statistics performSelector:@selector(javaScriptObjectTypeCounts)] : nil;
    names = [counts objectEnumerator];
    while ((name = [names nextObject]) != nil) {
        if ([counts countForObject:name] >= 2000)
            [types addObject:[NSString stringWithFormat:@"%@ %u", name, (unsigned)[counts countForObject:name]]];
    }
    NSLog(@"Captain Polliwog: memory: JS objects %lu, global objects %lu, protected %lu, cached pages %lu, fonts %lu | %@ | big types: %@",
          (unsigned long)CPStatisticCount(statistics, @"javaScriptObjectsCount"),
          (unsigned long)CPStatisticCount(statistics, @"javaScriptGlobalObjectsCount"),
          (unsigned long)CPStatisticCount(statistics, @"javaScriptProtectedObjectsCount"),
          (unsigned long)CPStatisticCount(statistics, @"cachedPageCount"),
          (unsigned long)CPStatisticCount(statistics, @"cachedFontDataCount"),
          [statistics respondsToSelector:@selector(memoryStatistics)] ? [[statistics performSelector:@selector(memoryStatistics)] description] : @"",
          [types componentsJoinedByString:@", "]);
}

// A link clicked in Mail, or anywhere else, arrives as a GetURL Apple Event.
// Without this, being the default browser would do nothing at all.
#ifndef kInternetEventClass
#define kInternetEventClass 'GURL'
#define kAEGetURL 'GURL'
#endif

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Registered before the application finishes launching, so that a link
    // that started it is not missed.
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:self
            andSelector:@selector(handleGetURLEvent:withReplyEvent:)
          forEventClass:kInternetEventClass
             andEventID:kAEGetURL];
}

// One place for every way a page arrives from outside: an Apple Event, a
// dropped file, or a document opened in the Finder.
// The panel CPDebugPanel opened, rather than the browser window behind it.
- (void)writeDebugPanelSnapshot
{
    NSString *panel = [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugPanel"];
    NSWindow *window = nil;

    if ([panel isEqualToString:@"preferences"])
        window = [[CPPreferencesController sharedController] window];
    else if ([panel isEqualToString:@"tabs"])
        window = [[browserWindows lastObject] window];
    else if ([panel isEqualToString:@"downloads"])
        window = [[CPDownloadsController sharedController] window];
    else if ([panel isEqualToString:@"bookmarks"])
        window = [[CPBookmarksController sharedController] window];
    if (window == nil)
        window = [NSApp keyWindow];
    if (window != nil)
        CPWriteWindowSnapshot(window);
}

- (void)openAddress:(NSString *)address
{
    CPBrowserWindowController *controller = [browserWindows lastObject];

    if (controller == nil) {
        controller = [self openBrowserWindow];
        [controller showWindow:self];
    }
    [[controller window] makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
    [controller addTabWithURL:[NSURL URLWithString:address] select:YES];
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply
{
    NSString *address = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];

    if ([address length] == 0)
        return;
    [self openAddress:address];
}

- (BOOL)application:(NSApplication *)application openFile:(NSString *)path
{
    NSURL *url = [NSURL fileURLWithPath:path];

    if (url == nil)
        return NO;
    [self openAddress:[url absoluteString]];
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSString *debugURL = [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugURL"];
    NSArray *debugTabs;
    unsigned index;

    if (CPDebugLogging() && [[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugMemory"])
        [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(logMemoryStatistics:) userInfo:nil repeats:YES];

    // Before any page can ask for video.
    [CPMediaRelay start];
    [CPAccelerator start];
    [CPSafeBrowsing start];
    // Anything written when the network was not there.
    [CPFeedback sendQueuedReports];
    // Not during launch: the first page matters more than the update feed.
    [[CPUpdater sharedUpdater] performSelector:@selector(checkInBackground)
                                    withObject:nil
                                    afterDelay:20.0];

    [[CPSettings sharedSettings] apply];
    // Testing aid: start straight in private browsing, without the question.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugPrivate"])
        [[CPPrivateBrowsing sharedPrivateBrowsing] setEnabled:YES];
    // Before any page loads, so the first visits are recorded too.
    [[CPHistory sharedHistory] start];
    if ([browserWindows count] == 0)
        [self newWindow:self];
    if (debugURL != nil)
        [[browserWindows lastObject] loadAddressString:debugURL];
    // After the first window, so it opens in front of something rather than
    // on an empty screen - and never when a test is driving the browser.
    if (debugURL == nil)
        [CPWelcome showIfNeeded];
    // Testing aid: CPDebugPanel opens a window at launch, for the test
    // scripts to photograph ("preferences", "downloads", "bookmarks").
    {
        NSString *panel = [[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugPanel"];
        if ([panel length] > 0 && CPDebugSnapshotPath() != nil)
            [self performSelector:@selector(writeDebugPanelSnapshot) withObject:nil afterDelay:6.0];
        if ([panel isEqualToString:@"preferences"])
            [self performSelector:@selector(showPreferences:) withObject:self afterDelay:1.0];
        else if ([panel isEqualToString:@"downloads"])
            [self performSelector:@selector(showDownloads:) withObject:self afterDelay:1.0];
        else if ([panel isEqualToString:@"tabs"])
            [[browserWindows lastObject] performSelector:@selector(toggleTabOverview:)
                                              withObject:self afterDelay:4.0];
        else if ([panel isEqualToString:@"bookmarks"])
            [[CPBookmarksController sharedController] performSelector:@selector(showWindow:)
                                                           withObject:self afterDelay:1.0];
    }

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
    // Undoes the private session's cookies before the store is written out.
    [[CPPrivateBrowsing sharedPrivateBrowsing] setEnabled:NO];
    [[CPHistory sharedHistory] save];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    if (!flag)
        [self newWindow:self];
    return YES;
}

@end
