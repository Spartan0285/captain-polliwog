/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPUpdateController.h"
#import "CPUpdater.h"

#define CPWindowWidth   460.0f
#define CPWindowHeight  330.0f

static NSTextField *CPUpdateLabel(NSView *parent, NSRect frame, NSString *text, BOOL small)
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
    } else
        [label setFont:[NSFont boldSystemFontOfSize:13.0f]];
    [parent addSubview:label];
    [label release];
    return label;
}

static NSButton *CPUpdateButton(NSView *parent, NSRect frame, NSString *title, id target, SEL action)
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:target];
    [button setAction:action];
    [parent addSubview:button];
    [button release];
    return button;
}

@interface CPUpdateController (Private)
- (void)buildWindow;
- (void)updaterChanged:(NSNotification *)note;
- (void)install:(id)sender;
- (void)later:(id)sender;
@end

@implementation CPUpdateController

+ (CPUpdateController *)sharedController
{
    static CPUpdateController *controller = nil;
    if (controller == nil)
        controller = [[CPUpdateController alloc] init];
    return controller;
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updaterChanged:)
                                                     name:CPUpdaterDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [window release];
    [super dealloc];
}

- (void)buildWindow
{
    NSView *content;
    NSRect frame = NSMakeRect(0, 0, CPWindowWidth, CPWindowHeight);

    if (window != nil)
        return;
    window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                           backing:NSBackingStoreBuffered
                                             defer:YES];
    [window setTitle:@"Software Update"];
    [window setReleasedWhenClosed:NO];
    content = [window contentView];

    headline = CPUpdateLabel(content, NSMakeRect(20, CPWindowHeight - 44, CPWindowWidth - 40, 20),
                             @"Checking for updates...", NO);
    detail = CPUpdateLabel(content, NSMakeRect(20, CPWindowHeight - 64, CPWindowWidth - 40, 16),
                           @"", YES);

    notesScroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(20, 60, CPWindowWidth - 40, CPWindowHeight - 136)];
    [notesScroll setHasVerticalScroller:YES];
    [notesScroll setBorderType:NSBezelBorder];
    [notesScroll setAutohidesScrollers:YES];
    notes = [[NSTextView alloc] initWithFrame:[[notesScroll contentView] bounds]];
    [notes setEditable:NO];
    [notes setDrawsBackground:YES];
    [notes setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [notes setTextContainerInset:NSMakeSize(4, 4)];
    [notesScroll setDocumentView:notes];
    [content addSubview:notesScroll];
    [notes release];
    [notesScroll release];

    progress = [[NSProgressIndicator alloc] initWithFrame:
        NSMakeRect(20, 26, CPWindowWidth - 220, 16)];
    [progress setStyle:NSProgressIndicatorBarStyle];
    [progress setIndeterminate:YES];
    [progress setDisplayedWhenStopped:NO];
    [content addSubview:progress];
    [progress release];

    installButton = CPUpdateButton(content, NSMakeRect(CPWindowWidth - 140, 16, 120, 32),
                                   @"Install Update", self, @selector(install:));
    [installButton setKeyEquivalent:@"\r"];
    laterButton = CPUpdateButton(content, NSMakeRect(CPWindowWidth - 245, 16, 100, 32),
                                 @"Not Now", self, @selector(later:));
    [window center];
}

- (void)show
{
    [self buildWindow];
    [self updaterChanged:nil];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)checkAsked:(id)sender
{
    [self show];
    [[CPUpdater sharedUpdater] checkAsked];
}

- (void)updaterChanged:(NSNotification *)note
{
    CPUpdater *updater = [CPUpdater sharedUpdater];
    CPUpdateState state = [updater state];
    NSString *current = [CPUpdater currentVersion];

    // An update found by the check at launch: say so, rather than staying
    // quiet in a window nobody opened.
    if (window == nil) {
        if (state == CPUpdateAvailable)
            [self show];
        return;
    }

    [progress setIndeterminate:YES];
    [progress stopAnimation:nil];
    [notesScroll setHidden:state == CPUpdateChecking];
    [installButton setEnabled:NO];
    [laterButton setTitle:@"Not Now"];

    switch (state) {
    case CPUpdateChecking:
        [headline setStringValue:@"Checking for updates..."];
        [detail setStringValue:[NSString stringWithFormat:@"This copy is version %@.", current]];
        [progress startAnimation:nil];
        break;

    case CPUpdateAvailable:
        [headline setStringValue:[NSString stringWithFormat:
            @"Captain Polliwog %@ is available.", [updater availableVersion]]];
        [detail setStringValue:[NSString stringWithFormat:
            @"This copy is version %@. The download is %.1f MB.",
            current, [updater downloadLength] / 1048576.0]];
        [notes setString:[updater releaseNotes] != nil
            ? [updater releaseNotes] : @"No release notes were published."];
        [installButton setEnabled:YES];
        break;

    case CPUpdateDownloading: {
        double fraction = [updater downloadProgress];
        [headline setStringValue:[NSString stringWithFormat:
            @"Downloading Captain Polliwog %@...", [updater availableVersion]]];
        [detail setStringValue:@"The download is checked against its signature before anything is installed."];
        if (fraction >= 0) {
            [progress setIndeterminate:NO];
            [progress setMinValue:0];
            [progress setMaxValue:1];
            [progress setDoubleValue:fraction];
        } else
            [progress startAnimation:nil];
        [laterButton setTitle:@"Cancel"];
        break;
    }

    case CPUpdateReadyToInstall:
        [headline setStringValue:[NSString stringWithFormat:
            @"Captain Polliwog %@ is ready to install.", [updater availableVersion]]];
        [detail setStringValue:@"Installing quits Captain Polliwog and opens the new version."];
        [installButton setTitle:@"Install and Relaunch"];
        [installButton setEnabled:YES];
        break;

    case CPUpdateUpToDate:
        [headline setStringValue:@"Captain Polliwog is up to date."];
        [detail setStringValue:[NSString stringWithFormat:@"Version %@ is the latest.", current]];
        [notes setString:@""];
        [laterButton setTitle:@"Close"];
        break;

    case CPUpdateFailed:
        [headline setStringValue:@"The update could not be checked."];
        [detail setStringValue:@""];
        [notes setString:[updater failureReason] != nil ? [updater failureReason] : @""];
        [laterButton setTitle:@"Close"];
        break;

    case CPUpdateIdle:
    default:
        [headline setStringValue:@"Software Update"];
        [detail setStringValue:[NSString stringWithFormat:@"This copy is version %@.", current]];
        break;
    }
}

- (void)install:(id)sender
{
    CPUpdater *updater = [CPUpdater sharedUpdater];

    if ([updater state] == CPUpdateReadyToInstall)
        [updater installAndRelaunch];
    else
        [updater download];
}

- (void)later:(id)sender
{
    if ([[CPUpdater sharedUpdater] state] == CPUpdateDownloading)
        [[CPUpdater sharedUpdater] cancel];
    [window orderOut:nil];
}

@end
