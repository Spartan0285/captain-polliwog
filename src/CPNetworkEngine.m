/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPNetworkEngine.h"
#import "CPNetworkTask.h"
#include <curl/curl.h>

@interface CPNetworkEngine (Private)
- (void)networkThread:(id)ignored;
- (void)runTransfers;
@end

@implementation CPNetworkEngine (Private)

- (void)networkThread:(id)ignored
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [self runTransfers];
    [pool release];
}

- (void)runTransfers
{
    int running = 0;

    while (1) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSArray *starting;
        NSArray *stopping;
        unsigned index;
        int pending = 0;
        CURLMsg *message;

        pthread_mutex_lock(&mutex);
        while ([pendingTasks count] == 0 && [cancelledTasks count] == 0 && [activeTasks count] == 0)
            pthread_cond_wait(&queueChanged, &mutex);
        starting = [pendingTasks copy];
        stopping = [cancelledTasks copy];
        [pendingTasks removeAllObjects];
        [cancelledTasks removeAllObjects];
        pthread_mutex_unlock(&mutex);

        for (index = 0; index < [stopping count]; index++) {
            CPNetworkTask *task = [stopping objectAtIndex:index];
            if ([activeTasks containsObject:task]) {
                curl_multi_remove_handle((CURLM *)multiHandle, [task easyHandle]);
                [task releaseHandle];
                [activeTasks removeObject:task];
            }
        }
        [stopping release];

        for (index = 0; index < [starting count]; index++) {
            CPNetworkTask *task = [starting objectAtIndex:index];
            if ([task isCancelled])
                continue;
            if ([task prepareHandle] &&
                curl_multi_add_handle((CURLM *)multiHandle, [task easyHandle]) == CURLM_OK) {
                [activeTasks addObject:task];
            } else {
                [task completeWithCurlCode:CURLE_FAILED_INIT];
                [task releaseHandle];
            }
        }
        [starting release];

        curl_multi_perform((CURLM *)multiHandle, &running);

        while ((message = curl_multi_info_read((CURLM *)multiHandle, &pending)) != NULL) {
            CPNetworkTask *task = nil;
            if (message->msg != CURLMSG_DONE)
                continue;
            curl_easy_getinfo(message->easy_handle, CURLINFO_PRIVATE, &task);
            if (task == nil)
                continue;
            [[task retain] autorelease];
            [task completeWithCurlCode:(int)message->data.result];
            curl_multi_remove_handle((CURLM *)multiHandle, message->easy_handle);
            [task releaseHandle];
            [activeTasks removeObject:task];
        }

        if ([activeTasks count] > 0) {
            int descriptors = 0;
            // Wakes early when startTask/cancelTask calls curl_multi_wakeup.
            curl_multi_poll((CURLM *)multiHandle, NULL, 0, 250, &descriptors);
        }
        [pool release];
    }
}

@end

@implementation CPNetworkEngine

+ (CPNetworkEngine *)sharedEngine
{
    static CPNetworkEngine *engine = nil;
    if (engine == nil)
        engine = [[CPNetworkEngine alloc] init];
    return engine;
}

+ (NSString *)certificateBundlePath
{
    return [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
}

- (id)init
{
    self = [super init];
    if (self == nil)
        return nil;

    curl_global_init(CURL_GLOBAL_DEFAULT);
    multiHandle = curl_multi_init();
    pthread_mutex_init(&mutex, NULL);
    pthread_cond_init(&queueChanged, NULL);
    pendingTasks = [[NSMutableArray alloc] init];
    activeTasks = [[NSMutableArray alloc] init];
    cancelledTasks = [[NSMutableArray alloc] init];

    // Six at a time matches what these machines can actually keep busy, and
    // keeps memory use predictable on a 256MB G3.
    curl_multi_setopt((CURLM *)multiHandle, CURLMOPT_MAX_TOTAL_CONNECTIONS, (long)6);
    curl_multi_setopt((CURLM *)multiHandle, CURLMOPT_MAX_HOST_CONNECTIONS, (long)4);
    curl_multi_setopt((CURLM *)multiHandle, CURLMOPT_MAXCONNECTS, (long)8);

    return self;
}

- (void)startTask:(CPNetworkTask *)task
{
    pthread_mutex_lock(&mutex);
    [pendingTasks addObject:task];
    if (!threadStarted) {
        threadStarted = YES;
        [NSThread detachNewThreadSelector:@selector(networkThread:) toTarget:self withObject:nil];
    }
    pthread_cond_signal(&queueChanged);
    pthread_mutex_unlock(&mutex);
    curl_multi_wakeup((CURLM *)multiHandle);
}

- (void)cancelTask:(CPNetworkTask *)task
{
    pthread_mutex_lock(&mutex);
    [cancelledTasks addObject:task];
    pthread_cond_signal(&queueChanged);
    pthread_mutex_unlock(&mutex);
    curl_multi_wakeup((CURLM *)multiHandle);
}

@end
