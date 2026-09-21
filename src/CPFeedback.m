/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPFeedback.h"
#import "CPAbout.h"
#include <sys/sysctl.h>
#include <stdlib.h>          /* arc4random */

// One endpoint for every app in this family; the "app" field says which.
// Changeable without a new build:
//   defaults write org.captainpolliwog.browser CPFeedbackURL <address>
static NSString * const CPFeedbackDefaultURL = @"https://www.cytrusretro.com/api/feedback";
static NSString * const CPFeedbackAppID = @"captain-polliwog";
// Not a secret - it is in the binary - but it keeps a public endpoint from
// being the first thing a scanner finds. The real limits are on the server.
static NSString * const CPFeedbackClientToken = @"garden-client-1";

#define CPShotMaxEdge 800.0f

static NSString *CPFeedbackURL(void)
{
    NSString *configured = [[NSUserDefaults standardUserDefaults] stringForKey:@"CPFeedbackURL"];
    return [configured length] > 0 ? configured : CPFeedbackDefaultURL;
}

static NSTextField *CPMakeLabel(NSString *text, NSRect frame)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];

    [field setStringValue:text != nil ? text : @""];
    [field setEditable:NO];
    [field setSelectable:NO];
    [field setBordered:NO];
    [field setDrawsBackground:NO];
    [field setFont:[NSFont systemFontOfSize:12]];
    return field;
}

#pragma mark The encodings Tiger's Foundation does not have

static NSString *CPBase64(NSData *data)
{
    static const char *alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char *bytes = [data bytes];
    unsigned length = (unsigned)[data length], i;
    NSMutableString *out = [NSMutableString stringWithCapacity:(length + 2) / 3 * 4];

    for (i = 0; i < length; i += 3) {
        unsigned long value = (unsigned long)bytes[i] << 16;
        int have = 1;
        if (i + 1 < length) { value |= (unsigned long)bytes[i + 1] << 8; have++; }
        if (i + 2 < length) { value |= (unsigned long)bytes[i + 2];      have++; }
        [out appendFormat:@"%c%c%c%c",
            alphabet[(value >> 18) & 0x3F], alphabet[(value >> 12) & 0x3F],
            have > 1 ? alphabet[(value >> 6) & 0x3F] : '=',
            have > 2 ? alphabet[value & 0x3F] : '='];
    }
    return out;
}

static NSString *CPJSONString(NSString *string)
{
    NSMutableString *out = [NSMutableString stringWithString:@"\""];
    unsigned i, length = [string length];

    for (i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        switch (c) {
        case '"':  [out appendString:@"\\\""]; break;
        case '\\': [out appendString:@"\\\\"]; break;
        case '\n': [out appendString:@"\\n"]; break;
        case '\r': [out appendString:@"\\r"]; break;
        case '\t': [out appendString:@"\\t"]; break;
        default:
            if (c < 0x20 || c > 0x7E)
                [out appendFormat:@"\\u%04x", (unsigned)c];
            else
                [out appendFormat:@"%C", c];
        }
    }
    [out appendString:@"\""];
    return out;
}

#pragma mark What this Mac is

static NSString *CPSysctlString(const char *name)
{
    char buffer[256];
    size_t length = sizeof buffer;

    if (sysctlbyname(name, buffer, &length, NULL, 0) != 0)
        return @"";
    buffer[sizeof buffer - 1] = 0;
    return [NSString stringWithUTF8String:buffer];
}

static NSString *CPSystemJSON(void)
{
    NSRect screen = [[NSScreen mainScreen] frame];
    unsigned long long memory = 0;
    size_t length = sizeof memory;
    SInt32 major = 10, minor = 4;
    NSString *engine;

    sysctlbyname("hw.memsize", &memory, &length, NULL, 0);
    Gestalt(gestaltSystemVersionMajor, &major);
    Gestalt(gestaltSystemVersionMinor, &minor);
    // Which WebKit answered: the bundled one, or the system's when the app
    // has been moved out of /Applications and lost its DYLD_FRAMEWORK_PATH.
    // That single fact explains a whole class of report.
    engine = [[NSBundle mainBundle] pathForResource:@"WebCore" ofType:@"framework"
                                        inDirectory:@"Frameworks"] != nil
             || [[NSFileManager defaultManager] fileExistsAtPath:
                    [[[NSBundle mainBundle] bundlePath]
                        stringByAppendingPathComponent:@"Contents/Frameworks/WebCore.framework"]]
             ? @"bundled" : @"system";

    return [NSString stringWithFormat:
        @"{\"os\":%@,\"arch\":%@,\"model\":%@,\"memoryMB\":%llu,\"screen\":%@,\"engine\":%@}",
        CPJSONString([NSString stringWithFormat:@"%d.%d", (int)major, (int)minor]),
        CPJSONString(CPSysctlString("hw.machine")),
        CPJSONString(CPSysctlString("hw.model")),
        memory / (1024 * 1024),
        CPJSONString([NSString stringWithFormat:@"%dx%d", (int)NSWidth(screen), (int)NSHeight(screen)]),
        CPJSONString(engine)];
}

@interface CPFeedback (Private)
- (void)build;
- (void)send:(id)sender;
- (void)cancel:(id)sender;
- (void)shotToggled:(id)sender;
- (NSString *)reportJSON;
- (void)postJSON:(NSString *)json;
- (void)queueJSON:(NSString *)json;
- (void)finishedWithSuccess:(BOOL)ok error:(NSString *)error;
@end

static NSMutableArray *liveReports = nil;   // retried quietly in the background

@implementation CPFeedback

+ (NSString *)outboxDirectory
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *directory = [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                NSUserDomainMask, YES) objectAtIndex:0]
                              stringByAppendingPathComponent:@"Captain Polliwog"];

    [files createDirectoryAtPath:directory attributes:nil];
    directory = [directory stringByAppendingPathComponent:@"Outbox"];
    [files createDirectoryAtPath:directory attributes:nil];
    return directory;
}

+ (void)openForWindow:(NSWindow *)aWindow page:(NSString *)pageDescription
{
    CPFeedback *feedback = [[self alloc] init];     // released when the window closes

    feedback->page = [pageDescription copy];
    if (aWindow != nil) {
        NSView *view = [[aWindow contentView] superview];
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
        [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bitmap];
        feedback->shot = [[NSImage alloc] initWithSize:[bitmap size]];
        [feedback->shot addRepresentation:bitmap];
    }
    [feedback build];
}

+ (void)sendQueuedReports
{
    NSString *directory = [self outboxDirectory];
    NSEnumerator *names = [[[NSFileManager defaultManager] directoryContentsAtPath:directory]
                              objectEnumerator];
    NSString *name;

    if (liveReports == nil)
        liveReports = [[NSMutableArray alloc] init];
    while ((name = [names nextObject]) != nil) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSString *json;
        CPFeedback *feedback;

        if (![[name pathExtension] isEqualToString:@"json"])
            continue;
        json = [NSString stringWithContentsOfFile:path];
        if ([json length] == 0) {
            [[NSFileManager defaultManager] removeFileAtPath:path handler:nil];
            continue;
        }
        feedback = [[self alloc] init];
        feedback->queuedPath = [path copy];
        [liveReports addObject:feedback];
        [feedback release];
        [feedback postJSON:json];
    }
}

- (void)dealloc
{
    [connection cancel];
    [connection release];
    [response release];
    [window release];
    [shot release];
    [page release];
    [reportID release];
    [queuedPath release];
    [super dealloc];
}

@end

@implementation CPFeedback (Private)

- (void)build
{
    NSRect frame = NSMakeRect(0, 0, 520, 470);
    NSView *content;
    NSScrollView *scroll;
    NSTextField *label;
    NSButton *cancelButton;
    float y;

    window = [[NSWindow alloc] initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                    backing:NSBackingStoreBuffered defer:NO];
    [window setTitle:@"Send Feedback"];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:self];
    content = [window contentView];
    y = frame.size.height - 46;

    // Symptoms a person can recognise, not causes they are not qualified to
    // guess at. The commonest first, because it is the default; "Something
    // else" last, because a pile of reports under it means this list is
    // wrong.
    label = CPMakeLabel(@"What is this about?", NSMakeRect(20, y, 220, 18));
    [content addSubview:label];
    topic = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(220, y - 4, 280, 26)] autorelease];
    [topic addItemWithTitle:@"A page did not load"];
    [topic addItemWithTitle:@"A page looked wrong"];
    [topic addItemWithTitle:@"Something on the page did not work"];
    [topic addItemWithTitle:@"It was too slow"];
    [topic addItemWithTitle:@"It quit unexpectedly"];
    [topic addItemWithTitle:@"A suggestion"];
    [topic addItemWithTitle:@"Something else"];
    [content addSubview:topic];
    y -= 36;

    label = CPMakeLabel(@"What happened?", NSMakeRect(20, y, 300, 18));
    [content addSubview:label];
    y -= 150;
    scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(20, y, 480, 144)] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    message = [[[NSTextView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
    [message setMinSize:NSMakeSize(0, 0)];
    [message setMaxSize:NSMakeSize(1e7f, 1e7f)];
    [message setVerticallyResizable:YES];
    [message setHorizontallyResizable:NO];
    [message setAutoresizingMask:NSViewWidthSizable];
    [[message textContainer] setWidthTracksTextView:YES];
    [message setFont:[NSFont systemFontOfSize:12]];
    [scroll setDocumentView:message];
    [content addSubview:scroll];
    y -= 30;

    // The parenthetical is doing real work: without it people either leave it
    // blank and wonder why nobody replied, or fill it in and wonder what else
    // they have signed up for.
    label = CPMakeLabel(@"Your email (only if you want an answer)", NSMakeRect(20, y, 300, 18));
    [content addSubview:label];
    email = [[[NSTextField alloc] initWithFrame:NSMakeRect(320, y - 3, 180, 22)] autorelease];
    [[email cell] setPlaceholderString:@"optional"];
    [content addSubview:email];
    y -= 40;

    includeShot = [[[NSButton alloc] initWithFrame:NSMakeRect(20, y, 320, 20)] autorelease];
    [includeShot setButtonType:NSSwitchButton];
    [includeShot setTitle:@"Include a picture of Captain Polliwog's window"];
    [includeShot setState:shot != nil ? NSOnState : NSOffState];
    [includeShot setEnabled:shot != nil];
    [includeShot setTarget:self];
    [includeShot setAction:@selector(shotToggled:)];
    [content addSubview:includeShot];

    // Exactly what would be sent, at a size where you can tell what is in it.
    shotView = [[[NSImageView alloc] initWithFrame:NSMakeRect(350, y - 54, 150, 76)] autorelease];
    [shotView setImageScaling:NSScaleProportionally];
    [shotView setImageFrameStyle:NSImageFrameGrayBezel];
    [shotView setImage:shot];
    [content addSubview:shotView];
    y -= 62;

    // Everything else that travels, named. Not "diagnostic information".
    label = CPMakeLabel([NSString stringWithFormat:
        @"Sent with this: Captain Polliwog %@, this Mac and its system, and the address of "
         "the page you were on. Nothing else, and nothing until you press Send.",
        [CPAbout versionLine]], NSMakeRect(20, y - 16, 320, 46));
    [label setFont:[NSFont systemFontOfSize:10]];
    [[label cell] setWraps:YES];
    [label setTextColor:[NSColor colorWithCalibratedWhite:0.42f alpha:1]];
    [content addSubview:label];

    status = CPMakeLabel(@"", NSMakeRect(20, 18, 300, 18));
    [status setFont:[NSFont systemFontOfSize:11]];
    [status setTextColor:[NSColor colorWithCalibratedWhite:0.42f alpha:1]];
    [content addSubview:status];

    sendButton = [[[NSButton alloc] initWithFrame:NSMakeRect(400, 14, 100, 30)] autorelease];
    [sendButton setBezelStyle:NSRoundedBezelStyle];
    [sendButton setTitle:@"Send"];
    [sendButton setKeyEquivalent:@"\r"];
    [sendButton setTarget:self];
    [sendButton setAction:@selector(send:)];
    [content addSubview:sendButton];

    cancelButton = [[[NSButton alloc] initWithFrame:NSMakeRect(296, 14, 100, 30)] autorelease];
    [cancelButton setBezelStyle:NSRoundedBezelStyle];
    [cancelButton setTitle:@"Cancel"];
    [cancelButton setKeyEquivalent:@"\033"];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancel:)];
    [content addSubview:cancelButton];

    [window center];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:message];
}

- (void)shotToggled:(id)sender
{
    [shotView setImage:[includeShot state] == NSOnState ? shot : nil];
}

- (void)cancel:(id)sender
{
    [window close];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self autorelease];
}

- (NSString *)reportJSON
{
    NSString *text = [[message textStorage] string];
    NSString *shotBase64 = @"";
    NSString *summary;
    NSRange newline;

    if ([includeShot state] == NSOnState && shot != nil) {
        // Scaled down: a 1280-pixel window is a lot to push through the sort
        // of connection these Macs are on, and the point is to see what it
        // looked like.
        NSSize size = [shot size];
        float scale = CPShotMaxEdge / (size.width > size.height ? size.width : size.height);
        NSBitmapImageRep *rep = nil;

        if (scale < 1.0f) {
            NSSize to = NSMakeSize(floorf(size.width * scale), floorf(size.height * scale));
            NSImage *small = [[[NSImage alloc] initWithSize:to] autorelease];
            [small lockFocus];
            [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
            [shot drawInRect:NSMakeRect(0, 0, to.width, to.height)
                    fromRect:NSMakeRect(0, 0, size.width, size.height)
                   operation:NSCompositeCopy fraction:1.0f];
            rep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:
                       NSMakeRect(0, 0, to.width, to.height)] autorelease];
            [small unlockFocus];
        } else {
            NSEnumerator *reps = [[shot representations] objectEnumerator];
            id candidate;
            while ((candidate = [reps nextObject]) != nil)
                if ([candidate isKindOfClass:[NSBitmapImageRep class]])
                    rep = candidate;
        }
        if (rep != nil)
            shotBase64 = CPBase64([rep representationUsingType:NSPNGFileType properties:nil]);
    }

    newline = [text rangeOfString:@"\n"];
    summary = newline.location == NSNotFound ? text : [text substringToIndex:newline.location];
    if ([summary length] > 90)
        summary = [summary substringToIndex:90];

    // A name this report keeps across retries, so one that was stored but
    // whose issue could not be opened does not become two.
    //
    // The random half has to be unguessable, not merely varied: the picture
    // that goes with a report is served from /api/shot/<app>/<id>.png with no
    // authentication - it has to be, so the issue can show it - so the id is
    // the only thing keeping one person's screenshot from anybody who asks.
    // random() without srandom() returns the same sequence on every Mac and
    // every launch (6b8b4567 first, every time), which would leave the
    // timestamp as the whole secret. arc4random seeds itself from the kernel.
    if (reportID == nil)
        reportID = [[NSString alloc] initWithFormat:@"%@-%08x%08x",
                       [[NSDate date] descriptionWithCalendarFormat:@"%Y%m%dT%H%M%S"
                                                           timeZone:nil locale:nil],
                       (unsigned)arc4random(), (unsigned)arc4random()];

    return [NSString stringWithFormat:
        @"{\"id\":%@,\"app\":%@,\"version\":%@,\"build\":%@,\"topic\":%@,\"summary\":%@,"
         "\"message\":%@,\"email\":%@,\"page\":%@,\"system\":%@,\"screenshot\":%@}",
        CPJSONString(reportID),
        CPJSONString(CPFeedbackAppID),
        CPJSONString([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]),
        CPJSONString([[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]),
        CPJSONString([topic titleOfSelectedItem]),
        CPJSONString(summary),
        CPJSONString(text),
        CPJSONString([email stringValue]),
        CPJSONString(page != nil ? page : @""),
        CPSystemJSON(),
        CPJSONString(shotBase64)];
}

- (void)send:(id)sender
{
    NSString *text = [[message textStorage] string];

    if ([[text stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] < 5) {
        NSRunAlertPanel(@"Say a little more",
                        @"A sentence about what happened is what makes a report worth sending.",
                        @"OK", nil, nil);
        return;
    }
    [sendButton setEnabled:NO];
    [status setStringValue:@"Sending..."];
    [self postJSON:[self reportJSON]];
}

- (void)postJSON:(NSString *)json
{
    NSMutableURLRequest *request;

    [connection cancel];
    [connection release];
    connection = nil;
    [response release];
    response = [[NSMutableData alloc] init];
    statusCode = 0;

    // Through the browser's own networking, which is how this reaches a site
    // that stopped accepting TLS 1.0 years ago.
    request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:CPFeedbackURL()]
                                      cachePolicy:NSURLRequestReloadIgnoringCacheData
                                  timeoutInterval:60.0];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:CPFeedbackClientToken forHTTPHeaderField:@"X-Feedback-Client"];
    [request setHTTPBody:[json dataUsingEncoding:NSUTF8StringEncoding]];
    connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
}

// Kept for the next launch rather than lost.
- (void)queueJSON:(NSString *)json
{
    NSString *path = queuedPath;

    if (path == nil)
        path = [[CPFeedback outboxDirectory] stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"%.0f.json",
                       [NSDate timeIntervalSinceReferenceDate] * 1000]];
    [json writeToFile:path atomically:YES];
}

#pragma mark The connection

- (void)connection:(NSURLConnection *)aConnection didReceiveResponse:(NSURLResponse *)aResponse
{
    statusCode = [aResponse respondsToSelector:@selector(statusCode)]
        ? (int)[(NSHTTPURLResponse *)aResponse statusCode] : 0;
    [response setLength:0];
}

- (void)connection:(NSURLConnection *)aConnection didReceiveData:(NSData *)data
{
    [response appendData:data];
}

- (void)connection:(NSURLConnection *)aConnection didFailWithError:(NSError *)error
{
    [self finishedWithSuccess:NO error:[error localizedDescription]];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection
{
    // 400 means it will never succeed, so it is not kept: a malformed report
    // retried for ever is worse than one lost.
    if (statusCode >= 200 && statusCode < 300)
        [self finishedWithSuccess:YES error:nil];
    else if (statusCode == 400)
        [self finishedWithSuccess:NO error:@"The report was refused as malformed."];
    else
        [self finishedWithSuccess:NO error:[NSString stringWithFormat:
            @"The site answered %d.", statusCode]];
}

- (void)finishedWithSuccess:(BOOL)ok error:(NSString *)error
{
    BOOL worthKeeping = !ok && statusCode != 400;

    if (window == nil) {
        // A queued report retrying quietly at launch.
        if ((ok || !worthKeeping) && queuedPath != nil)
            [[NSFileManager defaultManager] removeFileAtPath:queuedPath handler:nil];
        [liveReports removeObject:self];
        return;
    }
    if (ok) {
        if (queuedPath != nil)
            [[NSFileManager defaultManager] removeFileAtPath:queuedPath handler:nil];
        [window close];
        NSRunAlertPanel(@"Thank you", @"Your report has been sent.", @"OK", nil, nil);
        return;
    }
    [sendButton setEnabled:YES];
    if (worthKeeping) {
        [self queueJSON:[self reportJSON]];
        [status setStringValue:@"Kept for later; it will go when the network is back."];
        NSRunAlertPanel(@"That could not be sent",
                        @"%@\n\nYour report has been kept and will be sent the next time "
                         "Captain Polliwog starts.", @"OK", nil, nil, error);
    } else {
        [status setStringValue:@"Not sent."];
        NSRunAlertPanel(@"That could not be sent", @"%@", @"OK", nil, nil, error);
    }
}

@end
