/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPUpdateController.h"
#import "CPWelcome.h"   /* CPApplicationIcon */
#include <math.h>
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
- (NSString *)versionLine;
- (void)fitToState:(CPUpdateState)state;
- (void)announce:(NSNumber *)which;
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

    // The icon, as an alert carries it: the same thing The Garden's update
    // window shows, and the quickest way to say which app is talking.
    {
        NSImageView *icon = [[NSImageView alloc] initWithFrame:
            NSMakeRect(20, CPWindowHeight - 70, 52, 52)];
        [icon setImage:CPApplicationIcon()];
        [icon setImageScaling:NSScaleProportionally];
        [icon setEditable:NO];
        [icon setAutoresizingMask:NSViewMinYMargin];
        [content addSubview:icon];
        [icon release];
    }
    headline = CPUpdateLabel(content, NSMakeRect(86, CPWindowHeight - 40, CPWindowWidth - 106, 20),
                             @"Checking for updates...", NO);
    detail = CPUpdateLabel(content, NSMakeRect(86, CPWindowHeight - 60, CPWindowWidth - 106, 16),
                           @"", YES);
    // The window changes height with what it has to say: a line and a bar
    // while checking, the release notes when there is something to install.
    // So the text is pinned to the top, the notes stretch, and the bar and
    // the buttons stay on the bottom edge.
    [headline setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [detail setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];

    notesScroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(20, 60, CPWindowWidth - 40, CPWindowHeight - 146)];
    [notesScroll setHasVerticalScroller:YES];
    [notesScroll setBorderType:NSBezelBorder];
    [notesScroll setAutohidesScrollers:YES];
    notes = [[NSTextView alloc] initWithFrame:[[notesScroll contentView] bounds]];
    [notes setEditable:NO];
    [notes setDrawsBackground:YES];
    [notes setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [notes setTextContainerInset:NSMakeSize(4, 4)];
    [notesScroll setDocumentView:notes];
    [notesScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:notesScroll];
    [notes release];
    [notesScroll release];

    // Left of the buttons, not under them: it used to run to width - 200
    // while the first button began at width - 245.
    progress = [[NSProgressIndicator alloc] initWithFrame:
        NSMakeRect(20, 24, CPWindowWidth - 275, 16)];
    [progress setStyle:NSProgressIndicatorBarStyle];
    [progress setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
    [progress setIndeterminate:YES];
    [progress setDisplayedWhenStopped:NO];
    [content addSubview:progress];
    [progress release];

    installButton = CPUpdateButton(content, NSMakeRect(CPWindowWidth - 140, 16, 120, 32),
                                   @"Install Update", self, @selector(install:));
    [installButton setKeyEquivalent:@"\r"];
    laterButton = CPUpdateButton(content, NSMakeRect(CPWindowWidth - 245, 16, 100, 32),
                                 @"Not Now", self, @selector(later:));
    [installButton setAutoresizingMask:NSViewMaxYMargin | NSViewMinXMargin];
    [laterButton setAutoresizingMask:NSViewMaxYMargin | NSViewMinXMargin];
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

    // The answer to a question somebody asked is a sentence, not a window:
    // an up-to-date copy or a check that failed goes the way The Garden's
    // does, as an alert with the icon, and the window is put away. Only an
    // update that exists needs the room for its release notes.
    if ((state == CPUpdateUpToDate || state == CPUpdateFailed) && [window isVisible]) {
        [window orderOut:nil];
        [self performSelector:@selector(announce:) withObject:[NSNumber numberWithInt:state]
                   afterDelay:0.0];
        return;
    }

    [progress setIndeterminate:YES];
    [progress stopAnimation:nil];
    [notesScroll setHidden:state == CPUpdateChecking || state == CPUpdateIdle];
    [installButton setHidden:state == CPUpdateChecking];
    [laterButton setHidden:state == CPUpdateChecking];
    [installButton setEnabled:NO];
    [laterButton setTitle:@"Not Now"];
    [self fitToState:state];

    switch (state) {
    case CPUpdateChecking:
        [headline setStringValue:@"Checking for updates..."];
        [detail setStringValue:[NSString stringWithFormat:@"This is version %@.", [self versionLine]]];
        [progress startAnimation:nil];
        break;

    case CPUpdateAvailable:
        [headline setStringValue:[NSString stringWithFormat:
            @"Captain Polliwog %@ is available.", [updater availableVersion]]];
        [detail setStringValue:[NSString stringWithFormat:
            @"This is version %@. The download is %.1f MB.",
            [self versionLine], [updater downloadLength] / 1048576.0]];
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
    case CPUpdateFailed:
        // Reached only when the window is not showing - a check at launch -
        // and then there is nothing worth interrupting anyone for.
        break;

    case CPUpdateIdle:
    default:
        [headline setStringValue:@"Software Update"];
        [detail setStringValue:[NSString stringWithFormat:@"This copy is version %@.", current]];
        break;
    }
}

// "0.3 (build 9)": the build is what tells two copies of 0.3 apart, and it
// is what anyone asking which one they have wants to know.
- (NSString *)versionLine
{
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString *version = [CPUpdater currentVersion];
    return build != nil ? [NSString stringWithFormat:@"%@ (build %@)", version, build] : version;
}

// Short while checking, tall when there are notes to read.
- (void)fitToState:(CPUpdateState)state
{
    BOOL compact = state == CPUpdateChecking || state == CPUpdateIdle;
    float height = compact ? 124.0f : CPWindowHeight;
    NSRect frame = [window frame];
    NSRect content = [[window contentView] frame];
    float chrome = NSHeight(frame) - NSHeight(content);

    if (fabsf(NSHeight(content) - height) < 1.0f)
        return;
    // Keep the top edge where it was, so the title bar does not jump.
    frame.origin.y += NSHeight(frame) - (height + chrome);
    frame.size.height = height + chrome;
    [window setFrame:frame display:YES animate:[window isVisible]];
}

- (void)announce:(NSNumber *)which
{
    CPUpdater *updater = [CPUpdater sharedUpdater];
    NSAlert *alert;

    if ([which intValue] == CPUpdateUpToDate) {
        alert = [NSAlert alertWithMessageText:@"Captain Polliwog is up to date"
                                defaultButton:@"OK" alternateButton:nil otherButton:nil
                    informativeTextWithFormat:@"This is version %@, the newest there is.",
                                              [self versionLine]];
    } else {
        NSString *reason = [updater failureReason];
        alert = [NSAlert alertWithMessageText:@"Updates could not be checked"
                                defaultButton:@"OK" alternateButton:nil otherButton:nil
                    informativeTextWithFormat:@"%@",
                    [reason length] > 0 ? reason
                        : @"The update server could not be reached. Try again when this Mac is online."];
    }
    // Set rather than left to NSAlert, which asks for -applicationIconImage:
    // that answers with the Dock's cache, and a freshly installed copy may
    // not be in it - which is exactly when someone checks for updates.
    [alert setIcon:CPApplicationIcon()];
    [NSApp activateIgnoringOtherApps:YES];
    [alert runModal];
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
