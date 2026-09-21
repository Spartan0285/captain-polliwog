/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAbout.h"
#import "CPAppDelegate.h"
#import "CPWelcome.h"

#define ABOUT_W 460.0
#define ABOUT_H 430.0
#define PAD     28.0

// Cytrus Software's lime, from the site, and the purple sampled from the
// app's own icon. Lime takes near-black and purple takes white; the other way
// round is unreadable on a CRT, and these are CRTs.
static NSColor *CPLime(void)      { return [NSColor colorWithCalibratedRed:0.659 green:0.847 blue:0.102 alpha:1]; }
static NSColor *CPLimeInk(void)   { return [NSColor colorWithCalibratedRed:0.102 green:0.165 blue:0.0   alpha:1]; }
static NSColor *CPPurple(void)    { return [NSColor colorWithCalibratedRed:0.435 green:0.180 blue:0.494 alpha:1]; }
static NSColor *CPSubtleText(void) { return [NSColor colorWithCalibratedWhite:0.42 alpha:1]; }

// 10.4 has no -bezierPathWithRoundedRect:.
static NSBezierPath *CPRoundRect(NSRect r, float radius)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    float x = NSMinX(r), y = NSMinY(r), w = NSWidth(r), h = NSHeight(r);

    if (radius > w / 2) radius = w / 2;
    if (radius > h / 2) radius = h / 2;
    [path moveToPoint:NSMakePoint(x + radius, y)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x + w, y) toPoint:NSMakePoint(x + w, y + h) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x + w, y + h) toPoint:NSMakePoint(x, y + h) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x, y + h) toPoint:NSMakePoint(x, y) radius:radius];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(x, y) toPoint:NSMakePoint(x + w, y) radius:radius];
    [path closePath];
    return path;
}

// An image, the right way up, in a view that draws top-down.
//
// -drawInRect: in a flipped view lands the image upside down: text drawing
// accounts for flippedness and image drawing does not. Flipping the
// transform about the destination rectangle puts it back without touching
// the NSImage, which matters because one of these can be the shared
// application icon and setting -setFlipped: on that would follow it
// everywhere else it is drawn.
static void CPDrawImage(NSImage *image, NSRect r)
{
    NSAffineTransform *flip = [NSAffineTransform transform];

    if (image == nil)
        return;
    [NSGraphicsContext saveGraphicsState];
    [flip translateXBy:0.0f yBy:NSMaxY(r) + NSMinY(r)];
    [flip scaleXBy:1.0f yBy:-1.0f];
    [flip concat];
    [image drawInRect:r fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
    [NSGraphicsContext restoreGraphicsState];
}

static void CPDrawText(NSString *text, NSRect r, NSFont *font, NSColor *colour)
{
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        font, NSFontAttributeName, colour, NSForegroundColorAttributeName, nil];
    [text drawInRect:r withAttributes:attributes];
}

#pragma mark A button with a colour of its own

// NSButton will not fill itself with an arbitrary colour on 10.4, so this
// draws the whole thing.
@interface CPColorButton : NSButton
{
    NSColor *fill, *ink;
}
- (void)setFill:(NSColor *)aFill ink:(NSColor *)anInk;
@end

@implementation CPColorButton

- (void)setFill:(NSColor *)aFill ink:(NSColor *)anInk
{
    [fill autorelease]; fill = [aFill retain];
    [ink autorelease];  ink = [anInk retain];
    [self setNeedsDisplay:YES];
}

- (void)dealloc { [fill release]; [ink release]; [super dealloc]; }

- (void)drawRect:(NSRect)dirty
{
    NSRect r = NSInsetRect([self bounds], 0.5f, 0.5f);
    NSColor *colour = fill != nil ? fill : [NSColor grayColor];
    NSDictionary *attributes;
    NSSize size;

    // NSButton has no -isHighlighted; its cell does.
    if ([[self cell] isHighlighted])
        colour = [colour blendedColorWithFraction:0.25f ofColor:[NSColor blackColor]];
    [colour set];
    [CPRoundRect(r, 6.0f) fill];
    [[colour blendedColorWithFraction:0.35f ofColor:[NSColor blackColor]] set];
    [CPRoundRect(r, 6.0f) stroke];

    attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:12], NSFontAttributeName,
        ink != nil ? ink : [NSColor whiteColor], NSForegroundColorAttributeName, nil];
    size = [[self title] sizeWithAttributes:attributes];
    [[self title] drawAtPoint:NSMakePoint(NSMidX(r) - size.width / 2, NSMidY(r) - size.height / 2)
               withAttributes:attributes];
}

@end

#pragma mark The window's contents

@interface CPAboutView : NSView
{
    NSImage *appIcon, *logo;
}
@end

@implementation CPAboutView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]) == nil)
        return nil;
    appIcon = [CPApplicationIcon() retain];
    // The whole lockup, rasterised where the brand's typeface exists. The
    // artwork's wordmark is live text in Ariana Pro, which no Mac here has,
    // so anything rendered on these machines would substitute a fallback
    // face - which is why this arrives as a finished image rather than a
    // mark to assemble a name beside.
    logo = [[NSImage alloc] initWithContentsOfFile:
               [[NSBundle mainBundle] pathForResource:@"cytruslogo" ofType:@"png"]];
    return self;
}

- (void)dealloc { [appIcon release]; [logo release]; [super dealloc]; }

// Drawing top-down reads in the order the text is written. Note that this
// also lays out subviews top-down, so the two buttons measure themselves
// from the bottom of the window by hand.
- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirty
{
    float w = NSWidth([self bounds]), y = PAD;
    NSString *stage = [CPAbout stage];

    [[NSColor whiteColor] set];
    NSRectFill(dirty);

    CPDrawImage(appIcon, NSMakeRect(PAD, y, 56, 56));
    CPDrawText(@"Captain Polliwog", NSMakeRect(PAD + 70, y + 2, w - PAD - 70, 26),
               [NSFont boldSystemFontOfSize:18], [NSColor blackColor]);
    CPDrawText([CPAbout versionLine], NSMakeRect(PAD + 70, y + 30, w - PAD - 70, 16),
               [NSFont systemFontOfSize:11], CPSubtleText());
    if ([stage length] > 0) {
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSFont boldSystemFontOfSize:10], NSFontAttributeName,
            [NSColor whiteColor], NSForegroundColorAttributeName, nil];
        NSSize size = [stage sizeWithAttributes:attributes];
        NSRect badge = NSMakeRect(PAD + 70, y + 46, size.width + 16, 16);
        [[NSColor colorWithCalibratedRed:0.80f green:0.35f blue:0.04f alpha:1] set];
        [CPRoundRect(badge, 8.0f) fill];
        [stage drawAtPoint:NSMakePoint(badge.origin.x + 8, badge.origin.y + 1) withAttributes:attributes];
    }
    y += 76;

    [[NSColor colorWithCalibratedWhite:0.87f alpha:1] set];
    NSRectFill(NSMakeRect(PAD, y, w - 2 * PAD, 1));
    y += 14;

    CPDrawText(@"This is an alpha build. Expect rough edges, and please say when you find one.",
               NSMakeRect(PAD, y, w - 2 * PAD, 32), [NSFont boldSystemFontOfSize:11], [NSColor blackColor]);
    y += 34;

    // What it is not, plainly and early.
    CPDrawText(@"Captain Polliwog is not made by Apple and is not Safari. It is built on "
                "WebKit, the same engine Safari uses, brought forward to a version that can "
                "still read the modern web - and it will not always agree with the browser "
                "on your other computer.",
               NSMakeRect(PAD, y, w - 2 * PAD, 64), [NSFont systemFontOfSize:11], [NSColor blackColor]);
    y += 66;

    CPDrawText(@"Cytrus Software (a.k.a. Cytrus Retro) is a personal side project by me, "
                "Adam Cipoletti, a Creative Director and Career Coach. You can find more of "
                "my vintage software and hardware projects at cytrusretro.com.",
               NSMakeRect(PAD, y, w - 2 * PAD, 58), [NSFont systemFontOfSize:11], [NSColor blackColor]);
    y += 56;

    // The lockup, centred, at the artwork's own proportions.
    if (logo != nil) {
        NSSize size = [logo size];
        float logoWidth = 260.0f;
        float logoHeight = size.width > 0 ? logoWidth * size.height / size.width : 68.0f;

        CPDrawImage(logo, NSMakeRect((w - logoWidth) / 2, y, logoWidth, logoHeight));
    }
}

@end

#pragma mark The window

@interface CPAbout (Private)
- (void)showWindow;
@end

static CPAbout *sharedAbout = nil;

@implementation CPAbout

+ (NSString *)stage
{
    NSString *stage = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CPBuildStage"];
    return [stage length] > 0 ? stage : nil;
}

+ (NSString *)versionLine
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    return [NSString stringWithFormat:@"Version %@ (build %@)",
            version != nil ? version : @"?", build != nil ? build : @"?"];
}

+ (void)show
{
    if (sharedAbout == nil)
        sharedAbout = [[self alloc] init];
    [sharedAbout showWindow];
}

- (void)showWindow
{
    if (window == nil) {
        NSRect frame = NSMakeRect(0, 0, ABOUT_W, ABOUT_H);
        CPAboutView *view;
        CPColorButton *cytrus, *coach;
        float buttonWidth = (ABOUT_W - 2 * PAD - 16) / 2;

        window = [[NSWindow alloc] initWithContentRect:frame
                      styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                        backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"About Captain Polliwog"];
        [window setReleasedWhenClosed:NO];

        view = [[[CPAboutView alloc] initWithFrame:frame] autorelease];
        [window setContentView:view];

        // The view draws top-down, which places subviews top-down too, so a
        // button at y = 24 would land over the icon. Measured from the
        // bottom by hand.
        cytrus = [[[CPColorButton alloc] initWithFrame:
                      NSMakeRect(PAD, ABOUT_H - 24 - 34, buttonWidth, 34)] autorelease];
        [cytrus setBordered:NO];
        [cytrus setTitle:@"cytrusretro.com"];
        [cytrus setFill:CPLime() ink:CPLimeInk()];
        [cytrus setTarget:self];
        [cytrus setAction:@selector(openCytrus:)];
        [view addSubview:cytrus];

        coach = [[[CPColorButton alloc] initWithFrame:
                     NSMakeRect(PAD + buttonWidth + 16, ABOUT_H - 24 - 34, buttonWidth, 34)] autorelease];
        [coach setBordered:NO];
        [coach setTitle:@"amcreativecoach.com"];
        [coach setFill:CPPurple() ink:[NSColor whiteColor]];
        [coach setTarget:self];
        [coach setAction:@selector(openCoach:)];
        [view addSubview:coach];

        [window center];
    }
    [window makeKeyAndOrderFront:nil];
}

// Every other app in this family has to ask where a link should open, because
// the browser the Mac came with stops at TLS 1.0 and these sites refuse it.
// This one is that browser, so it just opens a tab.
- (void)openCytrus:(id)sender
{
    [(CPAppDelegate *)[NSApp delegate] openAddress:@"https://www.cytrusretro.com/"];
}

- (void)openCoach:(id)sender
{
    [(CPAppDelegate *)[NSApp delegate] openAddress:@"https://www.amcreativecoach.com/"];
}

@end
