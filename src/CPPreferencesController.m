/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPPreferencesController.h"
#import "CPSettings.h"
#import "CPSiteModes.h"
#import "CPDebugSnapshot.h"

#define CPWindowWidth   520.0f
#define CPWindowHeight  500.0f

static NSTextField *CPLabel(NSView *parent, NSRect frame, NSString *text, BOOL small, BOOL rightAligned)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];

    [label setStringValue:text];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    if (small) {
        [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [label setTextColor:[NSColor darkGrayColor]];
    }
    if (rightAligned)
        [label setAlignment:NSRightTextAlignment];
    [parent addSubview:label];
    [label release];
    return label;
}

static NSButton *CPButton(NSView *parent, NSRect frame, NSString *title, id target, SEL action)
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];

    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [button setTarget:target];
    [button setAction:action];
    [parent addSubview:button];
    [button release];
    return button;
}

@interface CPPreferencesController (Private)
- (void)buildInterface;
- (void)refresh;
@end

@implementation CPPreferencesController (Private)

// The performance switches: each a setting's getter and setter, a title
// and what it costs or saves.
static struct {
    NSString *getter;           // selector names: @selector isn't constant here
    NSString *setter;
    NSString *title;
    NSString *note;
} CPSwitches[] = {
    { @"loadsImages", @"setLoadsImages:", @"Load images", @"Off, pages load far faster and use less memory." },
    { @"showsAnimatedImages", @"setShowsAnimatedImages:", @"Animate images", @"GIF animations keep the processor busy." },
    { @"webGLEnabled", @"setWebGLEnabled:", @"Allow 3D graphics (WebGL)", @"Slow on these Macs; pages fall back without it." },
    { @"javaScriptEnabled", @"setJavaScriptEnabled:", @"Run JavaScript", @"Most sites need it; Reader never does." },
    { @"blocksAdsAndTrackers", @"setBlocksAdsAndTrackers:", @"Block ads and trackers", @"Often the heaviest part of a page." },
    { @"playsVideo", @"setPlaysVideo:", @"Play video and audio", @"Takes effect when Captain Polliwog next opens." },
    { @"autoplaysVideo", @"setAutoplaysVideo:", @"Let video play by itself", @"Off, video waits for a click." },
    { @"usesCompatibilityScripts", @"setUsesCompatibilityScripts:", @"Add newer web features", @"Helps modern sites; takes effect on next open." },
    { @"stopsLongScripts", @"setStopsLongScripts:", @"Stop scripts that run too long", @"Keeps a runaway page from freezing the browser." },
    { @"releasesMemoryUnderPressure", @"setReleasesMemoryUnderPressure:", @"Free memory when this Mac runs low", @"Pages you return to may redraw more slowly." },
    { NULL, NULL, nil, nil }
};

- (void)buildInterface
{
    NSView *content = [[self window] contentView];
    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(10.0f, 10.0f, CPWindowWidth - 20.0f, CPWindowHeight - 20.0f)];
    NSTabViewItem *item;
    NSView *view;
    float top;
    unsigned i;

    [content addSubview:tabs];
    [tabs release];

    // General
    item = [[[NSTabViewItem alloc] initWithIdentifier:@"general"] autorelease];
    [item setLabel:@"General"];
    view = [item view];
    top = CPWindowHeight - 90.0f;

    CPLabel(view, NSMakeRect(10.0f, top, 120.0f, 17.0f), @"Home page:", NO, YES);
    homePageField = [[NSTextField alloc] initWithFrame:NSMakeRect(138.0f, top - 2.0f, 310.0f, 22.0f)];
    [homePageField setTarget:self];
    [homePageField setAction:@selector(homePageChanged:)];
    [[homePageField cell] setSendsActionOnEndEditing:YES];
    [[homePageField cell] setScrollable:YES];
    [view addSubview:homePageField];
    [homePageField release];
    CPLabel(view, NSMakeRect(138.0f, top - 22.0f, 320.0f, 14.0f), @"Empty for the start page: Favorites and Top Sites.", YES, NO);
    CPButton(view, NSMakeRect(134.0f, top - 50.0f, 130.0f, 24.0f), @"Use Current Page", self, @selector(useCurrentPageAsHome:));

    top -= 88.0f;
    CPLabel(view, NSMakeRect(10.0f, top, 120.0f, 17.0f), @"New tabs open:", NO, YES);
    newTabPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(136.0f, top - 4.0f, 200.0f, 26.0f)];
    [newTabPopUp addItemWithTitle:@"Start Page"];
    [newTabPopUp addItemWithTitle:@"Home Page"];
    [newTabPopUp addItemWithTitle:@"Blank Page"];
    [newTabPopUp setTarget:self];
    [newTabPopUp setAction:@selector(newTabPageChanged:)];
    [view addSubview:newTabPopUp];
    [newTabPopUp release];

    top -= 42.0f;
    CPLabel(view, NSMakeRect(10.0f, top, 120.0f, 17.0f), @"Show websites as:", NO, YES);
    siteModePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(136.0f, top - 4.0f, 200.0f, 26.0f)];
    [siteModePopUp addItemWithTitle:@"Desktop"];
    [siteModePopUp addItemWithTitle:@"Mobile (lighter)"];
    [siteModePopUp addItemWithTitle:@"Basic (lightest)"];
    [siteModePopUp setTarget:self];
    [siteModePopUp setAction:@selector(siteModeChanged:)];
    [view addSubview:siteModePopUp];
    [siteModePopUp release];
    CPLabel(view, NSMakeRect(138.0f, top - 26.0f, 330.0f, 14.0f),
            @"For one site, use the aA button in the address bar.", YES, NO);

    top -= 62.0f;
    CPLabel(view, NSMakeRect(10.0f, top, 120.0f, 17.0f), @"Save downloads to:", NO, YES);
    downloadsField = CPLabel(view, NSMakeRect(138.0f, top + 1.0f, 230.0f, 14.0f), @"", YES, NO);
    [[downloadsField cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    CPButton(view, NSMakeRect(370.0f, top - 5.0f, 90.0f, 24.0f), @"Choose...", self, @selector(chooseDownloadsFolder:));
    [tabs addTabViewItem:item];

    // Performance
    item = [[[NSTabViewItem alloc] initWithIdentifier:@"performance"] autorelease];
    [item setLabel:@"Performance"];
    view = [item view];
    top = CPWindowHeight - 86.0f;

    CPLabel(view, NSMakeRect(10.0f, top, 110.0f, 17.0f), @"Memory use:", NO, YES);
    memoryPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(126.0f, top - 4.0f, 170.0f, 26.0f)];
    [memoryPopUp addItemWithTitle:@"Automatic"];
    [memoryPopUp addItemWithTitle:@"256MB machine"];
    [memoryPopUp addItemWithTitle:@"512MB machine"];
    [memoryPopUp addItemWithTitle:@"1GB or more"];
    [memoryPopUp setTarget:self];
    [memoryPopUp setAction:@selector(memoryProfileChanged:)];
    [view addSubview:memoryPopUp];
    [memoryPopUp release];
    memoryExplanation = CPLabel(view, NSMakeRect(128.0f, top - 22.0f, 340.0f, 14.0f), @"", YES, NO);

    top -= 44.0f;
    CPLabel(view, NSMakeRect(10.0f, top, 110.0f, 17.0f), @"Disk cache:", NO, YES);
    diskSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(128.0f, top - 2.0f, 50.0f, 22.0f)];
    [diskSizeField setTarget:self];
    [diskSizeField setAction:@selector(diskSizeChanged:)];
    [[diskSizeField cell] setSendsActionOnEndEditing:YES];
    [view addSubview:diskSizeField];
    [diskSizeField release];
    CPLabel(view, NSMakeRect(182.0f, top, 26.0f, 17.0f), @"MB", NO, NO);
    diskSizeNote = CPLabel(view, NSMakeRect(208.0f, top, 260.0f, 14.0f), @"", YES, NO);
    top -= 22.0f;
    locationField = CPLabel(view, NSMakeRect(128.0f, top, 340.0f, 14.0f), @"", YES, NO);
    top -= 28.0f;
    CPButton(view, NSMakeRect(124.0f, top, 86.0f, 24.0f), @"Choose...", self, @selector(chooseCacheLocation:));
    CPButton(view, NSMakeRect(212.0f, top, 100.0f, 24.0f), @"Use Default", self, @selector(useDefaultCacheLocation:));
    CPButton(view, NSMakeRect(314.0f, top, 110.0f, 24.0f), @"Empty Cache", self, @selector(clearCacheNow:));

    top -= 30.0f;
    for (i = 0; CPSwitches[i].title != nil; i++) {
        NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(18.0f, top, 250.0f, 18.0f)];
        [box setButtonType:NSSwitchButton];
        [box setTitle:CPSwitches[i].title];
        [box setTag:i];
        [box setTarget:self];
        [box setAction:@selector(switchChanged:)];
        [view addSubview:box];
        [switchBoxes addObject:box];
        [box release];
        CPLabel(view, NSMakeRect(272.0f, top + 1.0f, 200.0f, 14.0f), CPSwitches[i].note, YES, NO);
        top -= 22.0f;
    }
    [tabs addTabViewItem:item];
}

- (void)refresh
{
    CPSettings *settings = [CPSettings sharedSettings];
    NSString *location = [settings diskCacheLocation];
    NSString *detected;

    [memoryPopUp selectItemAtIndex:(int)[settings memoryProfile]];
    [siteModePopUp selectItemAtIndex:(int)[CPSiteModes defaultMode]];

    switch ([settings effectiveMemoryProfile]) {
    case CPMemoryProfileSmall:
        detected = @"small: 2MB in memory, no page history kept in memory";
        break;
    case CPMemoryProfileMedium:
        detected = @"medium: 6MB in memory, recent pages kept for Back";
        break;
    default:
        detected = @"large: 12MB in memory, recent pages kept for Back";
        break;
    }
    [memoryExplanation setStringValue:[NSString stringWithFormat:@"Using %@", detected]];

    [diskSizeField setIntValue:(int)[settings diskCacheMegabytes]];
    [diskSizeNote setStringValue:[NSString stringWithFormat:@"0 means automatic (%u MB); %.1f MB in use",
                                  [settings effectiveDiskCacheMegabytes],
                                  (double)[settings diskCacheBytesInUse] / (1024.0 * 1024.0)]];
    [locationField setStringValue:([location length] > 0) ? [settings resolvedDiskCachePath]
                                                          : @"Default (inside your Library folder)"];
    {
        unsigned i;
        for (i = 0; i < [switchBoxes count]; i++)
            [[switchBoxes objectAtIndex:i] setState:([settings performSelector:NSSelectorFromString(CPSwitches[i].getter)] ? NSOnState : NSOffState)];
    }
    [homePageField setStringValue:[settings homePage]];
    [newTabPopUp selectItemAtIndex:(int)[settings newTabPage]];
    [downloadsField setStringValue:[[settings downloadsFolder] stringByAbbreviatingWithTildeInPath]];
}

@end

@implementation CPPreferencesController

+ (CPPreferencesController *)sharedController
{
    static CPPreferencesController *controller = nil;
    if (controller == nil)
        controller = [[CPPreferencesController alloc] init];
    return controller;
}

- (id)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:
                        NSMakeRect(0.0f, 0.0f, CPWindowWidth, CPWindowHeight)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    [window setTitle:@"Preferences"];
    [window center];

    self = [super initWithWindow:window];
    [window release];
    if (self == nil)
        return nil;

    switchBoxes = [[NSMutableArray alloc] init];
    [self buildInterface];
    [self refresh];
    return self;
}

- (void)showWindow:(id)sender
{
    [self refresh];
    [super showWindow:sender];
}

- (void)writeDebugSnapshot
{
    CPWriteWindowSnapshot([self window]);
}

- (IBAction)memoryProfileChanged:(id)sender
{
    [[CPSettings sharedSettings] setMemoryProfile:(CPMemoryProfile)[memoryPopUp indexOfSelectedItem]];
    [self refresh];
}

- (IBAction)diskSizeChanged:(id)sender
{
    int megabytes = [diskSizeField intValue];

    if (megabytes < 0)
        megabytes = 0;
    [[CPSettings sharedSettings] setDiskCacheMegabytes:(unsigned)megabytes];
    [self refresh];
}

- (IBAction)chooseCacheLocation:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];

    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:@"Use Folder"];
    [panel setMessage:@"Choose where Captain Polliwog keeps its cache. "
                      @"A fast drive helps most."];
    if ([panel runModalForDirectory:NSHomeDirectory() file:nil types:nil] == NSOKButton)
        [[CPSettings sharedSettings] setDiskCacheLocation:[panel filename]];
    [self refresh];
}

- (IBAction)useDefaultCacheLocation:(id)sender
{
    [[CPSettings sharedSettings] setDiskCacheLocation:nil];
    [self refresh];
}

- (IBAction)clearCacheNow:(id)sender
{
    [[CPSettings sharedSettings] clearCaches];
    [self refresh];
}

- (IBAction)chooseDownloadsFolder:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];

    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:@"Use Folder"];
    if ([panel runModalForDirectory:[[CPSettings sharedSettings] downloadsFolder] file:nil types:nil] == NSOKButton)
        [[CPSettings sharedSettings] setDownloadsFolder:[panel filename]];
    [self refresh];
}

- (IBAction)siteModeChanged:(id)sender
{
    [CPSiteModes setDefaultMode:(CPSiteMode)[siteModePopUp indexOfSelectedItem]];
    [self refresh];
}

- (IBAction)switchChanged:(id)sender
{
    int index = [sender tag];
    BOOL on = [sender state] == NSOnState;
    NSMethodSignature *signature = [[CPSettings sharedSettings] methodSignatureForSelector:NSSelectorFromString(CPSwitches[index].setter)];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:[CPSettings sharedSettings]];
    [invocation setSelector:NSSelectorFromString(CPSwitches[index].setter)];
    [invocation setArgument:&on atIndex:2];
    [invocation invoke];
    [self refresh];
}

- (IBAction)homePageChanged:(id)sender
{
    NSString *home = [[homePageField stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([home length] && [home rangeOfString:@"://"].location == NSNotFound)
        home = [@"http://" stringByAppendingString:home];
    [[CPSettings sharedSettings] setHomePage:home];
    [self refresh];
}

- (IBAction)useCurrentPageAsHome:(id)sender
{
    id controller = [[NSApp mainWindow] windowController];
    NSURL *url = nil;
    if ([controller respondsToSelector:@selector(selectedTab)])
        url = [[controller performSelector:@selector(selectedTab)] URL];
    if ([[url scheme] hasPrefix:@"http"])
        [[CPSettings sharedSettings] setHomePage:[url absoluteString]];
    [self refresh];
}

- (IBAction)newTabPageChanged:(id)sender
{
    [[CPSettings sharedSettings] setNewTabPage:(CPNewTabPage)[newTabPopUp indexOfSelectedItem]];
}

@end
