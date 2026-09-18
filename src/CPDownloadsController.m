/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPDownloadsController.h"
#import "CPDownload.h"
#import "CPSettings.h"
#import "CPDebugSnapshot.h"

#define CPRowHeight 52.0f
#define CPWindowWidth 440.0f

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
    CPTagButton
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

@interface CPDownloadsController (Private)
- (NSView *)rowForDownload:(CPDownload *)download;
- (void)layoutRows;
- (void)updateRow:(NSView *)row forDownload:(CPDownload *)download;
- (void)downloadChanged:(NSNotification *)notification;
- (void)rowButtonClicked:(id)sender;
- (void)writeDebugSnapshot;
@end

@implementation CPDownloadsController (Private)

- (NSView *)rowForDownload:(CPDownload *)download
{
    NSView *row = [[[NSView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, CPWindowWidth, CPRowHeight)] autorelease];
    NSTextField *label;
    NSProgressIndicator *bar;
    NSButton *button;

    [row setAutoresizingMask:NSViewWidthSizable];

    label = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0f, 30.0f, CPWindowWidth - 136.0f, 17.0f)];
    [label setTag:CPTagName];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    [[label cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [label setAutoresizingMask:NSViewWidthSizable];
    [row addSubview:label];
    [label release];

    bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12.0f, 18.0f, CPWindowWidth - 136.0f, 12.0f)];
    [bar setStyle:NSProgressIndicatorBarStyle];
    [bar setControlSize:NSSmallControlSize];
    [bar setMinValue:0.0];
    [bar setMaxValue:1.0];
    [bar setAutoresizingMask:NSViewWidthSizable];
    [row addSubview:bar];
    [bar release];

    label = [[NSTextField alloc] initWithFrame:NSMakeRect(12.0f, 2.0f, CPWindowWidth - 136.0f, 14.0f)];
    [label setTag:CPTagStatus];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [label setTextColor:[NSColor darkGrayColor]];
    [label setAutoresizingMask:NSViewWidthSizable];
    [row addSubview:label];
    [label release];

    button = [[NSButton alloc] initWithFrame:NSMakeRect(CPWindowWidth - 120.0f, 14.0f, 112.0f, 24.0f)];
    [button setTag:CPTagButton];
    [button setBezelStyle:NSRoundedBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [button setTarget:self];
    [button setAction:@selector(rowButtonClicked:)];
    [button setAutoresizingMask:NSViewMinXMargin];
    [row addSubview:button];
    [button release];

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
    double fraction = [download fractionDone];
    BOOL active = ([download state] == CPDownloadActive);

    [[row viewWithTag:CPTagName] setStringValue:[download filename]];
    [[row viewWithTag:CPTagStatus] setStringValue:[download statusText]];

    [bar setHidden:!active];
    if (active) {
        [bar setIndeterminate:(fraction < 0.0)];
        if (fraction >= 0.0)
            [bar setDoubleValue:fraction];
        else
            [bar startAnimation:self];
    } else {
        [bar stopAnimation:self];
    }

    if (active)
        [button setTitle:@"Stop"];
    else if ([download state] == CPDownloadFinished)
        [button setTitle:@"Show in Finder"];
    else
        [button setTitle:@"Remove"];
}

- (void)downloadChanged:(NSNotification *)notification
{
    CPDownload *download = [notification object];
    unsigned index = [downloads indexOfObjectIdenticalTo:download];

    if (index == NSNotFound)
        return;
    [self updateRow:[[list subviews] objectAtIndex:index] forDownload:download];

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
    switch ([download state]) {
    case CPDownloadActive:
        [download cancel];
        break;
    case CPDownloadFinished:
        [[NSWorkspace sharedWorkspace] selectFile:[download path] inFileViewerRootedAtPath:@""];
        break;
    default:
        [row removeFromSuperview];
        [downloads removeObjectAtIndex:index];
        [self layoutRows];
        break;
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
    [window setMinSize:NSMakeSize(320.0f, 160.0f)];
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
    [download start];
    return download;
}

- (BOOL)hasActiveDownloads
{
    unsigned index;
    for (index = 0; index < [downloads count]; index++) {
        if ([[downloads objectAtIndex:index] state] == CPDownloadActive)
            return YES;
    }
    return NO;
}

- (IBAction)clearFinished:(id)sender
{
    int index;
    NSArray *rows = [[[list subviews] copy] autorelease];

    for (index = [downloads count] - 1; index >= 0; index--) {
        if ([[downloads objectAtIndex:index] state] != CPDownloadActive) {
            [[rows objectAtIndex:index] removeFromSuperview];
            [downloads removeObjectAtIndex:index];
        }
    }
    [self layoutRows];
}

@end
