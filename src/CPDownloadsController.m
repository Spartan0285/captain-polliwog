/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPDownloadsController.h"
#import "CPDownload.h"
#import "CPSettings.h"
#import "CPDebugSnapshot.h"

#define CPRowHeight 52.0f
#define CPWindowWidth 440.0f
#define CPTextWidth (CPWindowWidth - 176.0f)
// More at once only splits the same connection and makes each one slower.
#define CPMaxActiveDownloads 2

// Top-to-bottom coordinates, so new rows simply go at the bottom.
@interface CPFlippedView : NSView
@end

@implementation CPFlippedView
- (BOOL)isFlipped
{
    return YES;
}
@end

// Views in a row are found again by tag when the download changes. The
// progress bar has no tag -- only controls do -- so it is found by class.
enum {
    CPTagName = 1,
    CPTagStatus,
    CPTagButton,            // Pause / Resume / Retry / Open
    CPTagSecondButton       // Stop / Show / Remove
};

static NSProgressIndicator *CPProgressBarInRow(NSView *row)
{
    NSArray *views = [row subviews];
    unsigned index;
    for (index = 0; index < [views count]; index++) {
        if ([[views objectAtIndex:index] isKindOfClass:[NSProgressIndicator class]])
            return [views objectAtIndex:index];
    }
    return nil;
}

static NSButton *CPRowButton(NSView *row, int tag, float x, float width, id target)
{
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, 14.0f, width, 24.0f)];
    [button setTag:tag];
    [button setBezelStyle:NSRoundedBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [button setTarget:target];
    [button setAction:@selector(rowButtonClicked:)];
    [button setAutoresizingMask:NSViewMinXMargin];
    [row addSubview:button];
    [button release];
    return button;
}

@interface CPDownloadsController (Private)
- (NSView *)rowForDownload:(CPDownload *)download;
- (void)layoutRows;
- (void)updateRow:(NSView *)row forDownload:(CPDownload *)download;
- (void)downloadChanged:(NSNotification *)notification;
- (void)rowButtonClicked:(id)sender;
- (void)startQueuedDownloads;
- (void)writeDebugSnapshot;
@end

@implementation CPDownloadsController (Private)

- (NSView *)rowForDownload:(CPDownload *)download
{
    NSView *row = [[[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, CPWindowWidth, CPRowHeight)] autorelease];
    NSTextField *label;
    NSProgressIndicator *bar;

    [row setAutoresizingMask:NSViewWidthSizable];

    label = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0f, 30.0f, CPTextWidth, 17.0f)];
    [label setTag:CPTagName];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    [[label cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [label setAutoresizingMask:NSViewWidthSizable];
    [row addSubview:label];
    [label release];

    bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12.0f, 18.0f, CPTextWidth, 12.0f)];
    [bar setStyle:NSProgressIndicatorBarStyle];
    [bar setControlSize:NSSmallControlSize];
    [bar setMinValue:0.0];
    [bar setMaxValue:1.0];
    [bar setAutoresizingMask:NSViewWidthSizable];
    [row addSubview:bar];
    [bar release];

    label = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0f, 2.0f, CPTextWidth, 14.0f)];
    [label setTag:CPTagStatus];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [label setTextColor:[NSColor darkGrayColor]];
    [label setAutoresizingMask:NSViewWidthSizable];
    [row addSubview:label];
    [label release];

    CPRowButton(row, CPTagButton, CPWindowWidth - 158.0f, 76.0f, self);
    CPRowButton(row, CPTagSecondButton, CPWindowWidth - 84.0f, 76.0f, self);
    return row;
}

- (void)layoutRows
{
    NSArray *rows = [list subviews];
    float width = NSWidth([[list superview] bounds]);
    unsigned index;

    [list setFrame:NSMakeRect(0.0f, 0.0f, width, MAX(CPRowHeight * [rows count],
                                                       NSHeight([[list superview] bounds])))];
    for (index = 0; index < [rows count]; index++)
        [[rows objectAtIndex:index] setFrame:NSMakeRect(0.0f, index * CPRowHeight, width, CPRowHeight)];
    [emptyLabel setHidden:([downloads count] > 0)];
}

- (void)updateRow:(NSView *)row forDownload:(CPDownload *)download
{
    NSProgressIndicator *bar = CPProgressBarInRow(row);
    NSButton *button = [row viewWithTag:CPTagButton];
    NSButton *second = [row viewWithTag:CPTagSecondButton];
    double fraction = [download fractionDone];
    CPDownloadState state = [download state];
    BOOL active = (state == CPDownloadActive);

    [[row viewWithTag:CPTagName] setStringValue:[download filename]];
    [[row viewWithTag:CPTagStatus] setStringValue:[download statusText]];

    // A paused download keeps its bar, standing still.
    [bar setHidden:!(active || state == CPDownloadPaused)];
    if (active && fraction < 0.0) {
        [bar setIndeterminate:YES];
        [bar startAnimation:self];
    } else {
        [bar stopAnimation:self];
        [bar setIndeterminate:NO];
        [bar setDoubleValue:(fraction >= 0.0 ? fraction : 0.0)];
    }

    switch (state) {
    case CPDownloadActive:
    case CPDownloadQueued:
        [button setTitle:@"Pause"];
        [second setTitle:@"Stop"];
        break;
    case CPDownloadPaused:
        [button setTitle:@"Resume"];
        [second setTitle:@"Stop"];
        break;
    case CPDownloadFinished:
        [button setTitle:@"Open"];
        [second setTitle:@"Show"];
        break;
    default:
        [button setTitle:@"Retry"];
        [second setTitle:@"Remove"];
        break;
    }
}

- (void)downloadChanged:(NSNotification *)notification
{
    CPDownload *download = [notification object];
    unsigned index = [downloads indexOfObjectIdenticalTo:download];

    if (index == NSNotFound)
        return;
    [self updateRow:[[list subviews] objectAtIndex:index] forDownload:download];

    // One finished, paused or joined the queue: perhaps it is another's turn.
    if ([download state] != CPDownloadActive)
        [self performSelector:@selector(startQueuedDownloads) withObject:nil afterDelay:0.0];

    if ([download state] == CPDownloadFinished || [download state] == CPDownloadFailed) {
        if (CPDebugSnapshotPath() != nil)
            [self performSelector:@selector(writeDebugSnapshot) withObject:nil afterDelay:1.0];
    }
}

- (void)rowButtonClicked:(id)sender
{
    NSView *row = [sender superview];
    unsigned index = [[list subviews] indexOfObjectIdenticalTo:row];
    CPDownload *download;

    if (index == NSNotFound)
        return;
    download = [downloads objectAtIndex:index];

    if ([sender tag] == CPTagButton) {
        switch ([download state]) {
        case CPDownloadActive:
        case CPDownloadQueued:
            [download pause];
            break;
        case CPDownloadFinished:
            if (![[NSWorkspace sharedWorkspace] openFile:[download path]])
                NSBeep();
            break;
        default:
            [download resume];
            break;
        }
        return;
    }

    switch ([download state]) {
    case CPDownloadActive:
    case CPDownloadQueued:
    case CPDownloadPaused:
        [download cancel];
        break;
    case CPDownloadFinished:
        [[NSWorkspace sharedWorkspace] selectFile:[download path] inFileViewerRootedAtPath:@""];
        break;
    default:
        // A failed download's partial file goes with it.
        if ([download state] == CPDownloadFailed)
            [[NSFileManager defaultManager] removeFileAtPath:[download path] handler:nil];
        [row removeFromSuperview];
        [downloads removeObjectAtIndex:index];
        [self layoutRows];
        break;
    }
}

- (void)startQueuedDownloads
{
    unsigned index, active = 0;

    for (index = 0; index < [downloads count]; index++) {
        if ([[downloads objectAtIndex:index] state] == CPDownloadActive)
            active++;
    }
    for (index = 0; index < [downloads count] && active < CPMaxActiveDownloads; index++) {
        CPDownload *download = [downloads objectAtIndex:index];
        if ([download state] == CPDownloadQueued) {
            [download start];
            active++;
        }
    }
}

- (void)writeDebugSnapshot
{
    CPWriteWindowSnapshot([self window]);
}

@end

@implementation CPDownloadsController

+ (CPDownloadsController *)sharedController
{
    static CPDownloadsController *controller = nil;
    if (controller == nil)
        controller = [[CPDownloadsController alloc] init];
    return controller;
}

- (id)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, CPWindowWidth, 300.0f)
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                                                              NSMiniaturizableWindowMask | NSResizableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    NSView *content = [window contentView];
    NSScrollView *scroller;
    NSButton *clear;

    [window setTitle:@"Downloads"];
    [window setMinSize:NSMakeSize(360.0f, 160.0f)];
    [window center];

    self = [super initWithWindow:window];
    [window release];
    if (self == nil)
        return nil;

    downloads = [[NSMutableArray alloc] init];

    scroller = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0f, 40.0f, CPWindowWidth, 260.0f)];
    [scroller setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [scroller setHasVerticalScroller:YES];
    [scroller setBorderType:NSNoBorder];
    list = [[CPFlippedView alloc] initWithFrame:[[scroller contentView] bounds]];
    [list setAutoresizingMask:NSViewWidthSizable];
    [scroller setDocumentView:list];
    [list release];
    [content addSubview:scroller];
    [scroller release];

    emptyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0f, 150.0f, CPWindowWidth, 20.0f)];
    [emptyLabel setStringValue:@"No downloads"];
    [emptyLabel setAlignment:NSCenterTextAlignment];
    [emptyLabel setEditable:NO];
    [emptyLabel setBezeled:NO];
    [emptyLabel setDrawsBackground:NO];
    [emptyLabel setTextColor:[NSColor grayColor]];
    [emptyLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin)];
    [content addSubview:emptyLabel];
    [emptyLabel release];

    clear = [[NSButton alloc] initWithFrame:NSMakeRect(10.0f, 8.0f, 80.0f, 24.0f)];
    [clear setBezelStyle:NSRoundedBezelStyle];
    [clear setTitle:@"Clear"];
    [clear setToolTip:@"Remove finished and stopped downloads from the list"];
    [clear setTarget:self];
    [clear setAction:@selector(clearFinished:)];
    [content addSubview:clear];
    [clear release];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadChanged:)
                                                 name:CPDownloadDidChangeNotification object:nil];
    [self layoutRows];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [downloads release];
    [super dealloc];
}

- (CPDownload *)startDownloadWithRequest:(NSURLRequest *)request suggestedFilename:(NSString *)filename
{
    CPDownload *download = [[[CPDownload alloc] initWithRequest:request
                                              suggestedFilename:filename
                                                         folder:[[CPSettings sharedSettings] downloadsFolder]] autorelease];
    NSView *row = [self rowForDownload:download];

    [downloads addObject:download];
    [list addSubview:row];
    [self layoutRows];
    [self updateRow:row forDownload:download];
    [self showWindow:self];
    [self startQueuedDownloads];
    // Debugging: pause the first download after two seconds and resume it
    // three seconds later, which exercises continuing a partial file.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CPDebugDownloadPause"] && [downloads count] == 1) {
        [download performSelector:@selector(pause) withObject:nil afterDelay:2.0];
        [download performSelector:@selector(resume) withObject:nil afterDelay:5.0];
    }
    return download;
}

- (BOOL)hasActiveDownloads
{
    unsigned index;
    for (index = 0; index < [downloads count]; index++) {
        CPDownloadState state = [[downloads objectAtIndex:index] state];
        if (state == CPDownloadActive || state == CPDownloadQueued)
            return YES;
    }
    return NO;
}

- (unsigned)activeDownloadCount
{
    unsigned index, count = 0;
    for (index = 0; index < [downloads count]; index++) {
        CPDownloadState state = [[downloads objectAtIndex:index] state];
        if (state == CPDownloadActive || state == CPDownloadQueued)
            count++;
    }
    return count;
}

- (IBAction)clearFinished:(id)sender
{
    int index;
    NSArray *rows = [[[list subviews] copy] autorelease];

    for (index = [downloads count] - 1; index >= 0; index--) {
        CPDownloadState state = [[downloads objectAtIndex:index] state];
        if (state == CPDownloadFinished || state == CPDownloadCancelled) {
            [[rows objectAtIndex:index] removeFromSuperview];
            [downloads removeObjectAtIndex:index];
        }
    }
    [self layoutRows];
}

@end
