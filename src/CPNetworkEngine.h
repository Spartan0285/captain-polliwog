/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPNetworkTask;

// One background thread runs every transfer through a single libcurl multi
// handle. A thread per request would cost far too much memory on a 256MB G3,
// and sharing one handle lets connections and TLS sessions be reused.
@interface CPNetworkEngine : NSObject
{
    void            *multiHandle;   // CURLM *
    NSCondition     *condition;     // guards the three queues below
    NSMutableArray  *pendingTasks;
    NSMutableArray  *activeTasks;
    NSMutableArray  *cancelledTasks;
    BOOL             threadStarted;
}

+ (CPNetworkEngine *)sharedEngine;

// Path to the bundled list of certificate authorities.
+ (NSString *)certificateBundlePath;

- (void)startTask:(CPNetworkTask *)task;
- (void)cancelTask:(CPNetworkTask *)task;

@end
