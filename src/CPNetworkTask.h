/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPCurlProtocol;

// One HTTP(S) transfer. Created on the main thread, driven on the network
// thread, and it hands results back to the main thread because WebKit must
// only ever be touched there.
@interface CPNetworkTask : NSObject
{
    NSURLRequest        *request;
    CPCurlProtocol      *protocol;      // retained until the transfer ends
    void                *easyHandle;    // CURL *
    void                *headerList;    // struct curl_slist *
    char                *errorBuffer;
    NSData              *uploadBody;    // kept alive while libcurl reads it
    NSMutableDictionary *responseHeaders;
    NSMutableArray      *responseHeaderOrder;
    int                  statusCode;
    NSString            *httpVersion;
    NSString            *redirectLocation;
    BOOL                 responseDelivered;
    BOOL                 cancelled;
}

- (id)initWithRequest:(NSURLRequest *)aRequest protocol:(CPCurlProtocol *)aProtocol;

- (NSURLRequest *)request;
- (CPCurlProtocol *)protocol;
- (void *)easyHandle;

- (BOOL)isCancelled;
- (void)markCancelled;

// Network thread: build and tear down the libcurl handle.
- (BOOL)prepareHandle;
- (void)releaseHandle;

// Network thread: called by the libcurl callbacks.
- (size_t)handleHeaderLine:(const char *)bytes length:(size_t)length;
- (size_t)handleBodyBytes:(const char *)bytes length:(size_t)length;
- (void)completeWithCurlCode:(int)code;

@end
