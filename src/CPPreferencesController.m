/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPPreferencesController.h"
#import "CPSettings.h"
#import "CPSiteModes.h"
#import "CPSiteSettings.h"
#import "CPDebugSnapshot.h"
#import "CPAccelerator.h"
#import "CPDefaultBrowser.h"

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
- (IBAction)makeDefaultBrowser:(id)sender;
- (IBAction)removeWebsiteSettings:(id)sender;
- (IBAction)removeAllWebsiteSettings:(id)sender;
- (IBAction)updatesChanged:(id)sender;
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

    top -= 40.0f;
    updatesBox = [[NSButton alloc] initWithFrame:NSMakeRect(18.0f, top, 440.0f, 18.0f)];
    [updatesBox setButtonType:NSSwitchButton];
    [updatesBox setTitle:@"Check for updates automatically"];
    [updatesBox setTarget:self];
    [updatesBox setAction:@selector(updatesChanged:)];
    [view addSubview:updatesBox];
    [updatesBox release];
    CPLabel(view, NSMakeRect(36.0f, top - 18.0f, 430.0f, 14.0f),
            @"Once a day. Nothing is ever installed without asking you first.", YES, NO);

    top -= 46.0f;
    CPLabel(view, NSMakeRect(10.0f, top, 120.0f, 17.0f), @"Default browser:", NO, YES);
    defaultBrowserStatus = CPLabel(view, NSMakeRect(138.0f, top + 1.0f, 200.0f, 14.0f), @"", YES, NO);
    defaultBrowserButton = CPButton(view, NSMakeRect(340.0f, top - 5.0f, 130.0f, 24.0f),
                                    @"Set as Default", self, @selector(makeDefaultBrowser:));
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

    // Websites: everything remembered about particular sites, in one place,
    // so a setting made months ago on one site can be found and undone.
    item = [[[NSTabViewItem alloc] initWithIdentifier:@"websites"] autorelease];
    [item setLabel:@"Websites"];
    view = [item view];
    top = CPWindowHeight - 90.0f;

    CPLabel(view, NSMakeRect(10.0f, top + 4.0f, 460.0f, 17.0f),
            @"Settings you have made for particular websites:", NO, NO);
    {
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
            NSMakeRect(10.0f, 58.0f, CPWindowWidth - 40.0f, top - 62.0f)];
        NSRect inner = NSMakeRect(0.0f, 0.0f, CPWindowWidth - 42.0f, top - 64.0f);
        struct { NSString *identifier; NSString *title; float width; } columns[] = {
            { @"site", @"Website", 170.0f }, { @"mode", @"Shown as", 80.0f },
            { @"text", @"Text", 46.0f }, { @"reader", @"Reader", 52.0f },
            { @"scripts", @"Scripts", 56.0f }, { @"images", @"Images", 56.0f },
            { nil, nil, 0.0f }
        };
        unsigned column;

        websitesTable = [[NSTableView alloc] initWithFrame:inner];
        for (column = 0; columns[column].identifier != nil; column++) {
            NSTableColumn *tableColumn = [[NSTableColumn alloc]
                initWithIdentifier:columns[column].identifier];
            [[tableColumn headerCell] setStringValue:columns[column].title];
            [tableColumn setWidth:columns[column].width];
            [tableColumn setEditable:NO];
            [websitesTable addTableColumn:tableColumn];
            [tableColumn release];
        }
        [websitesTable setDataSource:self];
        [websitesTable setDelegate:self];
        [websitesTable setAllowsMultipleSelection:YES];
        [websitesTable setUsesAlternatingRowBackgroundColors:YES];
        [scroll setDocumentView:websitesTable];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];
        [scroll setAutohidesScrollers:YES];
        [view addSubview:scroll];
        [websitesTable release];
        [scroll release];
    }
    CPButton(view, NSMakeRect(10.0f, 24.0f, 90.0f, 24.0f), @"Remove", self,
             @selector(removeWebsiteSettings:));
    CPButton(view, NSMakeRect(104.0f, 24.0f, 120.0f, 24.0f), @"Remove All", self,
             @selector(removeAllWebsiteSettings:));
    CPLabel(view, NSMakeRect(232.0f, 30.0f, 250.0f, 14.0f),
            @"A removed site goes back to the defaults.", YES, NO);
    [tabs addTabViewItem:item];

    // PowerEmu's Web Accelerator (see CPAccelerator.h)
    item = [[[NSTabViewItem alloc] initWithIdentifier:@"poweremu"] autorelease];
    [item setLabel:@"PowerEmu"];
    view = [item view];
    top = CPWindowHeight - 90.0f;

    acceleratorBox = [[NSButton alloc] initWithFrame:NSMakeRect(18.0f, top, 440.0f, 18.0f)];
    [acceleratorBox setButtonType:NSSwitchButton];
    [acceleratorBox setTitle:@"Speed up browsing with PowerEmu when it's available"];
    [acceleratorBox setTarget:self];
    [acceleratorBox setAction:@selector(acceleratorChanged:)];
    [view addSubview:acceleratorBox];
    [acceleratorBox release];
    CPLabel(view, NSMakeRect(36.0f, top - 46.0f, 420.0f, 42.0f),
            @"PowerEmu fetches pages with a modern Mac's networking, converts images this Mac can't show, "
            @"shrinks huge ones, and leaves out ads and trackers. Without it, pages load as usual.", YES, NO);

    top -= 76.0f;
    acceleratorStatus = CPLabel(view, NSMakeRect(36.0f, top, 420.0f, 28.0f), @"", NO, NO);

    top -= 44.0f;
    CPLabel(view, NSMakeRect(10.0f, top, 120.0f, 17.0f), @"Pairing code:", NO, YES);
    pairingField = [[NSTextField alloc] initWithFrame:NSMakeRect(138.0f, top - 2.0f, 120.0f, 22.0f)];
    [[pairingField cell] setPlaceholderString:@"0000-0000"];
    [pairingField setTarget:self];
    [pairingField setAction:@selector(pairingCodeChanged:)];
    [view addSubview:pairingField];
    [pairingField release];
    CPButton(view, NSMakeRect(262.0f, top - 5.0f, 80.0f, 24.0f), @"Use", self, @selector(pairingCodeChanged:));
    CPLabel(view, NSMakeRect(138.0f, top - 64.0f, 320.0f, 56.0f),
            @"Only for PowerEmu on another Mac; inside a PowerEmu virtual Mac none is needed. "
            @"The code is shown in PowerEmu's Service Hub. The connection to the other Mac isn't encrypted, "
            @"so pages you visit, sign-ins included, cross your network in the clear.", YES, NO);
    [tabs addTabViewItem:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(acceleratorStatusChanged:)
                                                 name:CPAcceleratorStatusDidChangeNotification object:nil];
}

- (void)acceleratorStatusChanged:(NSNotification *)notification
{
    [acceleratorStatus setStringValue:[CPAccelerator statusDescription]];
}

- (IBAction)acceleratorChanged:(id)sender
{
    [CPAccelerator setEnabled:[acceleratorBox state] == NSOnState];
}

#pragma mark The websites table

- (int)numberOfRowsInTableView:(NSTableView *)table
{
    return (int)[configuredSites count];
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(int)row
{
    NSString *site = row < (int)[configuredSites count] ? [configuredSites objectAtIndex:row] : nil;
    NSString *identifier = [column identifier];
    NSDictionary *settings = [CPSiteSettings settingsForSite:site];
    NSURL *url;

    if (site == nil)
        return nil;
    if ([identifier isEqualToString:@"site"])
        return site;

    url = [NSURL URLWithString:[@"http://" stringByAppendingString:site]];
    if ([identifier isEqualToString:@"mode"]) {
        if (![CPSiteModes hasModeForURL:url])
            return @"";
        return [CPSiteModes nameForMode:[CPSiteModes modeForSite:site]];
    }
    if ([identifier isEqualToString:@"text"]) {
        NSNumber *size = [settings objectForKey:@"textSize"];
        return size != nil ? [NSString stringWithFormat:@"%d%%", (int)([size floatValue] * 100)] : @"";
    }
    if ([identifier isEqualToString:@"reader"])
        return [[settings objectForKey:@"reader"] boolValue] ? @"On" : @"";
    if ([identifier isEqualToString:@"scripts"]) {
        NSNumber *enabled = [settings objectForKey:@"javaScript"];
        return enabled != nil ? ([enabled boolValue] ? @"On" : @"Off") : @"";
    }
    if ([identifier isEqualToString:@"images"]) {
        NSNumber *enabled = [settings objectForKey:@"images"];
        return enabled != nil ? ([enabled boolValue] ? @"On" : @"Off") : @"";
    }
    return nil;
}

// Forgetting a site means forgetting both halves: its settings and its
// version, which are kept apart (CPSiteSettings and CPSiteModes).
- (IBAction)removeWebsiteSettings:(id)sender
{
    NSEnumerator *rows = [websitesTable selectedRowEnumerator];
    NSMutableArray *chosen = [NSMutableArray array];
    NSNumber *row;
    unsigned index;

    while ((row = [rows nextObject]) != nil) {
        if ([row intValue] < (int)[configuredSites count])
            [chosen addObject:[configuredSites objectAtIndex:[row intValue]]];
    }
    for (index = 0; index < [chosen count]; index++) {
        [CPSiteSettings removeSettingsForSite:[chosen objectAtIndex:index]];
        [CPSiteModes removeModeForSite:[chosen objectAtIndex:index]];
    }
    [self refresh];
}

- (IBAction)removeAllWebsiteSettings:(id)sender
{
    NSArray *sites = [[configuredSites copy] autorelease];
    unsigned index;

    for (index = 0; index < [sites count]; index++) {
        [CPSiteSettings removeSettingsForSite:[sites objectAtIndex:index]];
        [CPSiteModes removeModeForSite:[sites objectAtIndex:index]];
    }
    [self refresh];
}

#pragma mark

- (IBAction)makeDefaultBrowser:(id)sender
{
    [CPDefaultBrowser makeDefault];
    [self refresh];
}

- (IBAction)updatesChanged:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:([updatesBox state] == NSOnState)
                                            forKey:@"CPChecksForUpdates"];
}

- (IBAction)pairingCodeChanged:(id)sender
{
    [CPAccelerator setPairingCode:[pairingField stringValue]];
    // Not shown again once saved.
    [pairingField setStringValue:@""];
    [[pairingField cell] setPlaceholderString:([[CPAccelerator pairingCode] length] > 0 ? @"Saved" : @"0000-0000")];
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
    [updatesBox setState:[[NSUserDefaults standardUserDefaults] boolForKey:@"CPChecksForUpdates"]
        ? NSOnState : NSOffState];
    {
        NSMutableSet *sites = [NSMutableSet setWithArray:[CPSiteSettings configuredSites]];
        [sites addObjectsFromArray:[CPSiteModes configuredSites]];
        [configuredSites release];
        configuredSites = [[[sites allObjects] sortedArrayUsingSelector:@selector(compare:)] retain];
        [websitesTable reloadData];
    }
    if ([CPDefaultBrowser isDefault]) {
        [defaultBrowserStatus setStringValue:@"Captain Polliwog"];
        [defaultBrowserButton setEnabled:NO];
    } else {
        NSString *name = [CPDefaultBrowser currentDefaultName];
        [defaultBrowserStatus setStringValue:name != nil ? name : @"another browser"];
        [defaultBrowserButton setEnabled:YES];
    }
    [acceleratorBox setState:[CPAccelerator isEnabled] ? NSOnState : NSOffState];
    [acceleratorStatus setStringValue:[CPAccelerator statusDescription]];
    [[pairingField cell] setPlaceholderString:([[CPAccelerator pairingCode] length] > 0 ? @"Saved" : @"0000-0000")];
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
