/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPWelcome.h"
#import "CPBookmarks.h"
#import "CPDefaultBrowser.h"
#import "CPExternalPlayer.h"
#import "CPDownloadsController.h"
#import "CPAppDelegate.h"
#include <sys/types.h>
#include <sys/sysctl.h>

static NSString * const CPWelcomeDoneKey = @"CPWelcomeCompleted";

// The last PowerPC build VideoLAN made. 2.0.10 is old, and it is what there
// is; nothing newer was ever built for these Macs.
static NSString * const CPVLCDownloadURL =
    @"https://get.videolan.org/vlc/2.0.10/macosx/vlc-2.0.10-powerpc.dmg";

#define WELCOME_W 520.0
#define WELCOME_H 460.0
#define PAGES     4

// AppIcon.png is the artwork the .icns was made from, and the one thing here
// that is certainly a real image at a real size.
NSImage *CPApplicationIcon(void)
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"png"];
    NSImage *image = path != nil
        ? [[[NSImage alloc] initWithContentsOfFile:path] autorelease] : nil;

    return image != nil ? image : [NSApp applicationIconImage];
}

static NSTextField *CPWelcomeLabel(NSRect frame, NSFont *font, BOOL centred)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];

    [field setEditable:NO];
    [field setSelectable:NO];
    [field setBordered:NO];
    [field setDrawsBackground:NO];
    [field setFont:font];
    [field setAlignment:centred ? NSCenterTextAlignment : NSLeftTextAlignment];
    [[field cell] setWraps:YES];
    return field;
}

@interface CPWelcome (Private)
- (void)build;
- (void)showPage:(int)which;
- (void)next:(id)sender;
- (void)skip:(id)sender;
- (void)doAction:(id)sender;
- (void)finish;
- (void)markDone;
- (void)layoutPage;
@end

static CPWelcome *sharedWelcome = nil;

@implementation CPWelcome

+ (BOOL)hasAltiVec
{
    int present = 0;
    size_t length = sizeof present;

    // hw.vectorunit is 1 on every G4 and G5 and 0 on a G3. On Intel the key
    // exists too and answers for SSE, which is not what this is asking, but
    // no PowerPC build of VLC is of any use there either.
    if (sysctlbyname("hw.vectorunit", &present, &length, NULL, 0) != 0)
        return NO;
    return present != 0;
}

+ (void)downloadVLC
{
    [[CPDownloadsController sharedController]
        startDownloadWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:CPVLCDownloadURL]]
               suggestedFilename:@"vlc-2.0.10-powerpc.dmg"];
}

+ (void)showIfNeeded
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:CPWelcomeDoneKey])
        return;
    [self show];
}

+ (void)show
{
    if (sharedWelcome == nil)
        sharedWelcome = [[self alloc] init];
    [sharedWelcome build];
}

+ (void)showAtStep:(int)step
{
    [self show];
    if (step >= 1 && step <= PAGES)
        [sharedWelcome showPage:step - 1];
}

- (void)dealloc
{
    [window release];
    [super dealloc];
}

@end

@implementation CPWelcome (Private)

- (void)build
{
    NSRect frame = NSMakeRect(0, 0, WELCOME_W, WELCOME_H);
    NSView *content;

    if (window != nil) {
        [window makeKeyAndOrderFront:nil];
        return;
    }
    window = [[NSWindow alloc] initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                    backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Welcome Aboard"];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:self];
    content = [window contentView];

    // The Captain, centred at the top, on every step.
    icon = [[[NSImageView alloc] initWithFrame:
                NSMakeRect((WELCOME_W - 96) / 2, WELCOME_H - 124, 96, 96)] autorelease];
    // The PNG rather than -applicationIconImage: on these systems that
    // answers with whatever the Dock has cached for the bundle, which for a
    // freshly installed app can be nothing at all.
    [icon setImage:CPApplicationIcon()];
    [icon setImageScaling:NSScaleProportionally];
    [icon setEditable:NO];
    [content addSubview:icon];

    heading = CPWelcomeLabel(NSMakeRect(40, WELCOME_H - 168, WELCOME_W - 80, 40),
                             [NSFont boldSystemFontOfSize:15], YES);
    [content addSubview:heading];

    body = CPWelcomeLabel(NSMakeRect(50, WELCOME_H - 300, WELCOME_W - 100, 124),
                          [NSFont systemFontOfSize:12], YES);
    [content addSubview:body];

    action = [[[NSButton alloc] initWithFrame:
                  NSMakeRect((WELCOME_W - 260) / 2, 132, 260, 32)] autorelease];
    [action setBezelStyle:NSRoundedBezelStyle];
    [action setTarget:self];
    [action setAction:@selector(doAction:)];
    [content addSubview:action];

    result = CPWelcomeLabel(NSMakeRect(50, 104, WELCOME_W - 100, 20),
                            [NSFont systemFontOfSize:11], YES);
    [result setTextColor:[NSColor colorWithCalibratedWhite:0.35f alpha:1]];
    [content addSubview:result];

    step = CPWelcomeLabel(NSMakeRect(24, 46, 140, 16), [NSFont systemFontOfSize:11], NO);
    [step setTextColor:[NSColor colorWithCalibratedWhite:0.45f alpha:1]];
    [content addSubview:step];

    // Ticked, because closing this window has always meant "done". Clearing
    // it is how someone says they would rather finish later, and then it
    // comes back at the next launch.
    againBox = [[[NSButton alloc] initWithFrame:NSMakeRect(22, 22, 250, 18)] autorelease];
    [againBox setButtonType:NSSwitchButton];
    [againBox setTitle:@"Don't show this again"];
    [againBox setState:NSOnState];
    [content addSubview:againBox];

    skipButton = [[[NSButton alloc] initWithFrame:NSMakeRect(WELCOME_W - 250, 20, 110, 30)] autorelease];
    [skipButton setBezelStyle:NSRoundedBezelStyle];
    [skipButton setTitle:@"Skip Setup"];
    [skipButton setTarget:self];
    [skipButton setAction:@selector(skip:)];
    [content addSubview:skipButton];

    nextButton = [[[NSButton alloc] initWithFrame:NSMakeRect(WELCOME_W - 134, 20, 110, 30)] autorelease];
    [nextButton setBezelStyle:NSRoundedBezelStyle];
    [nextButton setKeyEquivalent:@"\r"];
    [nextButton setTarget:self];
    [nextButton setAction:@selector(next:)];
    [content addSubview:nextButton];

    page = 0;
    [self showPage:0];
    [window center];
    [window makeKeyAndOrderFront:nil];
}

- (void)showPage:(int)which
{
    NSArray *players;
    NSString *player = nil;    // the fast one found, if any

    page = which;
    [result setStringValue:@""];
    [action setHidden:NO];
    [action setEnabled:YES];
    [step setStringValue:[NSString stringWithFormat:@"Step %d of %d", page + 1, PAGES]];
    [nextButton setTitle:page == PAGES - 1 ? @"Start Browsing" : @"Next"];
    [skipButton setHidden:page == PAGES - 1];

    switch (page) {
    case 0:
        [heading setStringValue:@"Hello there, matey! I'm your Captain."];
        [body setStringValue:
            @"Together we are going to surf the high seas \xE2\x80\x94 the modern web, on a Mac "
             "that was told some time ago it had seen enough of it.\n\n"
             "Would you like to bring your ports of call across? I can fetch the bookmarks "
             "you already keep in Safari."];
        [action setTitle:@"Import Bookmarks from Safari"];
        break;

    case 1:
        [heading setStringValue:@"I know there be other vessels you might fancy."];
        [body setStringValue:
            @"But my ship be a beaut. She's the only lass for the job \xE2\x80\x94 the browser "
             "this Mac came with stopped being able to reach most of the web years ago.\n\n"
             "Shall I take the wheel when something else opens a link?"];
        if ([CPDefaultBrowser isDefault]) {
            [action setHidden:YES];
            [result setStringValue:@"Already at the helm \xE2\x80\x94 I'm your default browser."];
        } else {
            [action setTitle:@"Make Captain Polliwog the Default"];
            [result setStringValue:[NSString stringWithFormat:@"Currently: %@",
                                    [CPDefaultBrowser currentDefaultName]]];
        }
        break;

    case 2:
        // QuickTime Player does not count: it is on every Mac, and its
        // decoder is the one the browser is already using.
        players = [CPExternalPlayer fasterPlayers];
        if ([players count] > 0)
            player = [CPExternalPlayer displayNameForPlayer:[players objectAtIndex:0]];

        [heading setStringValue:@"I'm going to be honest with you."];
        if (player != nil) {
            [body setStringValue:[NSString stringWithFormat:
                @"We need someone else in the crew to make it through this \xE2\x80\x94 and I "
                 "see you already have them.\n\n"
                 "%@ is aboard. When you find a video, use the green button on it, or "
                 "right-click, and I'll hand it over to %@, which decodes video far faster "
                 "than this Mac can manage inside a web page.", player, player]];
            [action setHidden:YES];
            [result setStringValue:[NSString stringWithFormat:
                @"%@ found in your Applications folder.", player]];
        } else if (![CPWelcome hasAltiVec]) {
            // Telling someone to install software that cannot run is worse
            // than saying nothing. VLC's PowerPC build carries AltiVec
            // instructions in its decoder and dies on the first frame
            // without a vector unit; this Mac has none.
            [body setStringValue:
                @"We need someone else in the crew to make it through this \xE2\x80\x94 but not "
                 "on this ship.\n\n"
                 "Video players like VLC decode with AltiVec, and this Mac's processor has no "
                 "vector unit, so the PowerPC build of VLC quits the moment it tries. I'll "
                 "play what I can myself. Smaller videos will fare better than large ones."];
            [action setHidden:YES];
        } else {
            [body setStringValue:
                @"We need someone else in the crew to make it through this.\n\n"
                 "Video on the web is H.264, and decoding it is the slowest thing this Mac will "
                 "ever be asked to do. VLC does the same work with AltiVec and manages about a "
                 "resolution more than I can. Install it and I'll hand videos over on request "
                 "\xE2\x80\x94 you'll find a green button on them."];
            [action setTitle:@"Download VLC for PowerPC"];
        }
        break;

    case 3:
        [heading setStringValue:@"That's the crew assembled."];
        [body setStringValue:
            @"One last honest word: this is an alpha. Some of the web will look wrong, and "
             "some of it will not load at all.\n\n"
             "That is worth knowing about, so there's a Send Feedback window in the Captain "
             "Polliwog menu. It takes a sentence and a picture of what you were looking at, "
             "and it is the fastest way to get something fixed.\n\n"
             "Now: where to first?"];
        [action setTitle:@"Send Feedback Later \xE2\x80\x94 Show Me How"];
        [action setHidden:YES];
        break;
    }
    [self layoutPage];
    [self layoutPage];
}

// How tall a wrapped label needs to be at a given width, as this system
// measures it. Tiger sets Lucida Grande a little taller than Leopard does, so
// boxes sized by eye on one clip the other; measuring is the only way to be
// right on both.
static float CPTextHeight(NSTextField *field, float width)
{
    NSSize size = [[field cell] cellSizeForBounds:NSMakeRect(0, 0, width, 10000.0f)];
    return ceilf(size.height);
}

// Top-down from the icon, each piece as tall as its words need, then the
// bottom bar - and the window grown to fit if a page asks for more room than
// it has. It only ever grows: shrinking between steps would make the Next
// button jump out from under the pointer.
- (void)layoutPage
{
    NSView *content = [window contentView];
    float width = WELCOME_W - 100.0f;
    float headingHeight = CPTextHeight(heading, WELCOME_W - 80.0f);
    float bodyHeight = CPTextHeight(body, width);
    BOOL showsAction = ![action isHidden];
    float bottomBar = 70.0f;            // checkbox, step count, the two buttons
    float below = bottomBar + 24.0f + (showsAction ? 32.0f + 12.0f : 0.0f);
    float needed = 24.0f + 96.0f + 16.0f + headingHeight + 12.0f + bodyHeight + 18.0f + below;
    float height = NSHeight([content frame]);
    float y;

    if (needed > height) {
        NSRect frame = [window frame];
        float grow = needed - height;
        frame.origin.y -= grow;         // keep the title bar where it was
        frame.size.height += grow;
        [window setFrame:frame display:YES animate:NO];
        height = needed;
    }

    y = height - 24.0f - 96.0f;
    [icon setFrame:NSMakeRect((WELCOME_W - 96) / 2, y, 96, 96)];
    y -= 16.0f + headingHeight;
    [heading setFrame:NSMakeRect(40, y, WELCOME_W - 80, headingHeight)];
    y -= 12.0f + bodyHeight;
    [body setFrame:NSMakeRect(50, y, width, bodyHeight)];
    y -= 18.0f;
    if (showsAction) {
        y -= 32.0f;
        [action setFrame:NSMakeRect((WELCOME_W - 260) / 2, y, 260, 32)];
        y -= 12.0f;
    }
    y -= 20.0f;
    [result setFrame:NSMakeRect(50, y, width, 20)];
    [content setNeedsDisplay:YES];
}

- (void)doAction:(id)sender
{
    switch (page) {
    case 0: {
        int count = [[CPBookmarkStore sharedStore] importSafariBookmarks];
        if (count < 0)
            [result setStringValue:@"No Safari bookmarks found on this Mac."];
        else
            [result setStringValue:[NSString stringWithFormat:
                @"Brought %d bookmark%s across.", count, count == 1 ? "" : "s"]];
        [action setEnabled:NO];
        break;
    }
    case 1:
        if ([CPDefaultBrowser makeDefault]) {
            [result setStringValue:@"Aye \xE2\x80\x94 I'm your default browser now."];
            [action setHidden:YES];
        } else {
            [result setStringValue:@"That didn't take. You can set it in Preferences."];
        }
        break;
    case 2:
        [CPWelcome downloadVLC];
        [result setStringValue:@"Downloading \xE2\x80\x94 open it when it lands and drag VLC to Applications."];
        [action setEnabled:NO];
        break;
    default:
        break;
    }
}

- (void)next:(id)sender
{
    if (page + 1 >= PAGES) {
        [self finish];
        return;
    }
    [self showPage:page + 1];
}

- (void)skip:(id)sender
{
    [self finish];
}

- (void)finish
{
    [self markDone];
    [window close];
}

// Written through at once rather than at the next quit: a browser that
// crashes before then would greet the same person all over again, which is
// the one thing a welcome screen must never do.
- (void)markDone
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL done = againBox == nil || [againBox state] == NSOnState;

    [defaults setBool:done forKey:CPWelcomeDoneKey];
    [defaults synchronize];
}

// Closing the window counts as having been through it; it is not a question
// worth asking twice.
- (void)windowWillClose:(NSNotification *)notification
{
    [self markDone];
}

@end
