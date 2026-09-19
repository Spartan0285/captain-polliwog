/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPNetworkTask;

extern NSString * const CPDownloadDidChangeNotification;

typedef enum {
    CPDownloadQueued,       // waiting for a turn
    CPDownloadActive,
    CPDownloadPaused,       // the partial file is kept
    CPDownloadFinished,
    CPDownloadFailed,
    CPDownloadCancelled
} CPDownloadState;

// One file being saved. It is written as "name.download" and renamed when
// complete, so a half-finished file is never mistaken for a whole one.
// It starts queued; CPDownloadsController decides when it runs.
@interface CPDownload : NSObject
{
    NSURLRequest    *request;
    NSString        *finalPath;
    NSString        *partialPath;
    CPNetworkTask   *task;
    CPDownloadState  state;
    long long        received;
    long long        expected;
    NSDate          *started;
    long long        receivedAtStart;   // for the rate: bytes already there on resuming
    NSString        *failureReason;
}

- (id)initWithRequest:(NSURLRequest *)aRequest
    suggestedFilename:(NSString *)filename
               folder:(NSString *)folder;

- (void)start;               // queued -> active
- (void)pause;               // active -> paused
- (void)resume;              // paused or failed -> queued, continuing the partial file
- (void)cancel;              // stops and deletes the partial file

- (NSString *)filename;
- (NSString *)path;
- (CPDownloadState)state;
- (NSString *)statusText;
- (double)fractionDone;     // -1 when the size is not known

@end
