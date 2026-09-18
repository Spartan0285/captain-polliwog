/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPPreferencesController.h"
#import "CPSettings.h"
#import "CPSiteModes.h"
#import "CPDebugSnapshot.h"

#define CPWindowWidth   520.0f
#define CPWindowHeight  402.0f

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

- (void)buildInterface
{
    NSView *content = [[self window] contentView];
    float top = CPWindowHeight - 36.0f;

    CPLabel(content, NSMakeRect(20.0f, top, 110.0f, 17.0f), @"Save downloads to:", NO, YES);
    downloadsField = CPLabel(content, NSMakeRect(138.0f, top + 1.0f, 260.0f, 14.0f), @"", YES, NO);
    [[downloadsField cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    CPButton(content, NSMakeRect(402.0f, top - 5.0f, 100.0f, 24.0f), @"Choose...",
             self, @selector(chooseDownloadsFolder:));

    top -= 42.0f;
    CPLabel(content, NSMakeRect(20.0f, top, 110.0f, 17.0f), @"Show websites as:", NO, YES);
    siteModePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(138.0f, top - 4.0f, 200.0f, 26.0f)];
    [siteModePopUp addItemWithTitle:@"Desktop"];
    [siteModePopUp addItemWithTitle:@"Mobile (lighter)"];
    [siteModePopUp addItemWithTitle:@"Basic (lightest)"];
    [siteModePopUp setTarget:self];
    [siteModePopUp setAction:@selector(siteModeChanged:)];
    [content addSubview:siteModePopUp];
    [siteModePopUp release];
    CPLabel(content, NSMakeRect(138.0f, top - 26.0f, 360.0f, 14.0f),
            @"Choose for a single site in View > Site Version.", YES, NO);

    top -= 54.0f;
    CPLabel(content, NSMakeRect(20.0f, top, 110.0f, 17.0f), @"Memory use:", NO, YES);
    memoryPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(138.0f, top - 4.0f, 200.0f, 26.0f)];
    [memoryPopUp addItemWithTitle:@"Automatic"];
    [memoryPopUp addItemWithTitle:@"256MB machine"];
    [memoryPopUp addItemWithTitle:@"512MB machine"];
    [memoryPopUp addItemWithTitle:@"1GB or more"];
    [memoryPopUp setTarget:self];
    [memoryPopUp setAction:@selector(memoryProfileChanged:)];
    [content addSubview:memoryPopUp];
    [memoryPopUp release];

    memoryExplanation = CPLabel(content, NSMakeRect(138.0f, top - 26.0f, 360.0f, 14.0f), @"", YES, NO);

    top -= 62.0f;
    CPLabel(content, NSMakeRect(20.0f, top, 110.0f, 17.0f), @"Disk cache:", NO, YES);
    diskSizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(138.0f, top - 2.0f, 60.0f, 22.0f)];
    [diskSizeField setTarget:self];
    [diskSizeField setAction:@selector(diskSizeChanged:)];
    [[diskSizeField cell] setSendsActionOnEndEditing:YES];
    [content addSubview:diskSizeField];
    [diskSizeField release];
    CPLabel(content, NSMakeRect(204.0f, top, 30.0f, 17.0f), @"MB", NO, NO);
    diskSizeNote = CPLabel(content, NSMakeRect(238.0f, top, 260.0f, 14.0f), @"", YES, NO);

    top -= 30.0f;
    CPLabel(content, NSMakeRect(20.0f, top, 110.0f, 17.0f), @"Location:", NO, YES);
    locationField = CPLabel(content, NSMakeRect(138.0f, top, 360.0f, 14.0f), @"", YES, NO);

    top -= 28.0f;
    CPButton(content, NSMakeRect(136.0f, top, 90.0f, 24.0f), @"Choose...",
             self, @selector(chooseCacheLocation:));
    CPButton(content, NSMakeRect(230.0f, top, 110.0f, 24.0f), @"Use Default",
             self, @selector(useDefaultCacheLocation:));
    CPButton(content, NSMakeRect(344.0f, top, 120.0f, 24.0f), @"Empty Cache",
             self, @selector(clearCacheNow:));

    top -= 36.0f;
    imagesCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(138.0f, top, 300.0f, 18.0f)];
    [imagesCheckbox setButtonType:NSSwitchButton];
    [imagesCheckbox setTitle:@"Load images"];
    [imagesCheckbox setTarget:self];
    [imagesCheckbox setAction:@selector(imagesChanged:)];
    [content addSubview:imagesCheckbox];
    [imagesCheckbox release];

    top -= 24.0f;
    memoryReliefCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(138.0f, top, 360.0f, 18.0f)];
    [memoryReliefCheckbox setButtonType:NSSwitchButton];
    [memoryReliefCheckbox setTitle:@"Free memory when this Mac runs low"];
    [memoryReliefCheckbox setTarget:self];
    [memoryReliefCheckbox setAction:@selector(memoryReliefChanged:)];
    [content addSubview:memoryReliefCheckbox];
    [memoryReliefCheckbox release];
    CPLabel(content, NSMakeRect(156.0f, top - 16.0f, 340.0f, 14.0f),
            @"Pages you return to may redraw their images more slowly.", YES, NO);

    CPLabel(content, NSMakeRect(20.0f, 16.0f, CPWindowWidth - 40.0f, 28.0f),
            @"A cached page skips the download and the secure handshake, "
            @"which is the slowest part on a G3.", YES, NO);
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
    [imagesCheckbox setState:([settings loadsImages] ? NSOnState : NSOffState)];
    [memoryReliefCheckbox setState:([settings releasesMemoryUnderPressure] ? NSOnState : NSOffState)];
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

- (IBAction)memoryReliefChanged:(id)sender
{
    [[CPSettings sharedSettings] setReleasesMemoryUnderPressure:([memoryReliefCheckbox state] == NSOnState)];
    [self refresh];
}

- (IBAction)siteModeChanged:(id)sender
{
    [CPSiteModes setDefaultMode:(CPSiteMode)[siteModePopUp indexOfSelectedItem]];
    [self refresh];
}

- (IBAction)imagesChanged:(id)sender
{
    [[CPSettings sharedSettings] setLoadsImages:([imagesCheckbox state] == NSOnState)];
    [self refresh];
}

@end
