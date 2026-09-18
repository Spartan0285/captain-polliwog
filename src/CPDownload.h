/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPNetworkTask;

extern NSString * const CPDownloadDidChangeNotification;

typedef enum {
    CPDownloadActive,
    CPDownloadFinished,
    CPDownloadFailed,
    CPDownloadCancelled
} CPDownloadState;

// One file being saved. It is written as "name.download" and renamed when
// complete, so a half-finished file is never mistaken for a whole one.
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
    NSString        *failureReason;
}

- (id)initWithRequest:(NSURLRequest *)aRequest
    suggestedFilename:(NSString *)filename
               folder:(NSString *)folder;

- (void)start;
- (void)cancel;

- (NSString *)filename;
- (NSString *)path;
- (CPDownloadState)state;
- (NSString *)statusText;
- (double)fractionDone;     // -1 when the size is not known

@end
