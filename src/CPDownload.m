/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPDownload.h"
#import "CPNetworkTask.h"
#import "CPNetworkEngine.h"
#import "CPDebugSnapshot.h"

NSString * const CPDownloadDidChangeNotification = @"CPDownloadDidChange";

static NSString *CPSizeText(long long bytes)
{
    if (bytes < 1024)
        return [NSString stringWithFormat:@"%lld bytes", bytes];
    if (bytes < 1024 * 1024)
        return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
}

// "name.zip", then "name 2.zip", "name 3.zip"... never replacing a file.
static NSString *CPUnusedPath(NSString *folder, NSString *filename)
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *base = [filename stringByDeletingPathExtension];
    NSString *extension = [filename pathExtension];
    NSString *candidate = [folder stringByAppendingPathComponent:filename];
    int number = 2;

    while ([files fileExistsAtPath:candidate] ||
           [files fileExistsAtPath:[candidate stringByAppendingPathExtension:@"download"]]) {
        NSString *name = [NSString stringWithFormat:@"%@ %d", base, number++];
        if ([extension length] > 0)
            name = [name stringByAppendingPathExtension:extension];
        candidate = [folder stringByAppendingPathComponent:name];
    }
    return candidate;
}

// A name that is safe to put in the Finder, whatever the server sent.
static NSString *CPCleanFilename(NSString *filename, NSURL *url)
{
    NSMutableString *clean;

    if ([filename length] == 0)
        filename = [[url path] lastPathComponent];
    if ([filename length] == 0 || [filename isEqualToString:@"/"])
        filename = @"download";
    clean = [NSMutableString stringWithString:filename];
    [clean replaceOccurrencesOfString:@"/" withString:@"-" options:0 range:NSMakeRange(0, [clean length])];
    [clean replaceOccurrencesOfString:@":" withString:@"-" options:0 range:NSMakeRange(0, [clean length])];
    while ([clean hasPrefix:@"."])
        [clean deleteCharactersInRange:NSMakeRange(0, 1)];
    return ([clean length] > 0) ? clean : @"download";
}

@interface CPDownload (Private)
- (void)changed;
@end

@implementation CPDownload (Private)

- (void)changed
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CPDownloadDidChangeNotification object:self];
}

@end

@implementation CPDownload

- (id)initWithRequest:(NSURLRequest *)aRequest
    suggestedFilename:(NSString *)filename
               folder:(NSString *)folder
{
    self = [super init];
    if (self == nil)
        return nil;

    request = [aRequest retain];
    finalPath = [CPUnusedPath(folder, CPCleanFilename(filename, [aRequest URL])) retain];
    partialPath = [[finalPath stringByAppendingPathExtension:@"download"] retain];
    expected = -1;
    return self;
}

- (void)dealloc
{
    [request release];
    [finalPath release];
    [partialPath release];
    [task release];
    [started release];
    [failureReason release];
    [super dealloc];
}

- (void)start
{
    started = [[NSDate date] retain];
    task = [[CPNetworkTask alloc] initWithRequest:request downloadPath:partialPath owner:self];
    if (task == nil) {
        state = CPDownloadFailed;
        failureReason = [@"The file could not be created. Check the downloads folder." retain];
        [self changed];
        return;
    }
    state = CPDownloadActive;
    [[CPNetworkEngine sharedEngine] startTask:task];
    [self changed];
}

- (void)cancel
{
    if (state != CPDownloadActive)
        return;
    state = CPDownloadCancelled;
    [task markCancelled];
    [task detachDownloadOwner];
    [[CPNetworkEngine sharedEngine] cancelTask:task];
    [task release];
    task = nil;
    [[NSFileManager defaultManager] removeFileAtPath:partialPath handler:nil];
    [self changed];
}

- (NSString *)filename
{
    return [finalPath lastPathComponent];
}

- (NSString *)path
{
    return (state == CPDownloadFinished) ? finalPath : partialPath;
}

- (CPDownloadState)state
{
    return state;
}

- (double)fractionDone
{
    if (expected <= 0)
        return -1.0;
    return (double)received / (double)expected;
}

- (NSString *)statusText
{
    double seconds = -[started timeIntervalSinceNow];
    double rate = (seconds > 0.5) ? (double)received / seconds : 0.0;

    switch (state) {
    case CPDownloadFinished:
        return [NSString stringWithFormat:@"%@, done", CPSizeText(received)];
    case CPDownloadFailed:
        return [NSString stringWithFormat:@"Failed: %@", failureReason];
    case CPDownloadCancelled:
        return @"Stopped";
    default:
        break;
    }
    if (expected > 0 && rate > 0.0)
        return [NSString stringWithFormat:@"%@ of %@ (%@/sec), about %.0f seconds left",
                CPSizeText(received), CPSizeText(expected), CPSizeText((long long)rate),
                (double)(expected - received) / rate];
    if (rate > 0.0)
        return [NSString stringWithFormat:@"%@ (%@/sec)", CPSizeText(received), CPSizeText((long long)rate)];
    return @"Starting...";
}

#pragma mark CPNetworkTask download owner

- (void)downloadReceivedBytes:(NSArray *)receivedAndExpected
{
    received = [[receivedAndExpected objectAtIndex:0] longLongValue];
    if ([[receivedAndExpected objectAtIndex:1] longLongValue] > 0)
        expected = [[receivedAndExpected objectAtIndex:1] longLongValue];
    [self changed];
}

- (void)downloadFinishedWithError:(NSError *)error
{
    NSFileManager *files = [NSFileManager defaultManager];

    if (state != CPDownloadActive)
        return;
    if (error != nil) {
        state = CPDownloadFailed;
        [failureReason release];
        failureReason = [[error localizedDescription] copy];
        [files removeFileAtPath:partialPath handler:nil];
    } else if (![files movePath:partialPath toPath:finalPath handler:nil]) {
        state = CPDownloadFailed;
        [failureReason release];
        failureReason = [@"The finished file could not be renamed." retain];
    } else {
        state = CPDownloadFinished;
    }
    if (CPDebugSnapshotPath() != nil)
        NSLog(@"Captain Polliwog: download %@ %lld bytes in %.1fs -> %@",
              (state == CPDownloadFinished ? @"finished" : @"failed"),
              received, -[started timeIntervalSinceNow], [self path]);
    [task release];
    task = nil;
    [self changed];
}

@end
