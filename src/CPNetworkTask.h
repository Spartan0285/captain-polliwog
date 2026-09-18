/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPCurlProtocol;

// What a task in download mode reports back, on the main thread.
@interface NSObject (CPDownloadTaskOwner)
- (void)downloadReceivedBytes:(NSArray *)receivedAndExpected;
- (void)downloadFinishedWithError:(NSError *)error;
@end

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
    NSCachedURLResponse *cachedResponse;    // a stored copy to revalidate
    NSHTTPURLResponse   *lastResponse;      // what this transfer returned
    NSMutableData       *cacheData;         // nil once too big to keep
    BOOL                 servedFromCache;
    int                  statusCode;
    NSString            *httpVersion;
    NSString            *redirectLocation;
    BOOL                 responseDelivered;
    BOOL                 cancelled;

    // Download mode: the body goes straight to a file on the network thread
    // and never passes through memory or the main thread.
    id                   downloadOwner;     // retained
    FILE                *downloadFile;
    long long            bytesWritten;
    long long            bytesExpected;
    double               lastProgressReport;
}

- (id)initWithRequest:(NSURLRequest *)aRequest
             protocol:(CPCurlProtocol *)aProtocol
       cachedResponse:(NSCachedURLResponse *)aCachedResponse;

// A download: follows redirects itself and writes the body to path.
- (id)initWithRequest:(NSURLRequest *)aRequest downloadPath:(NSString *)path owner:(id)owner;

- (NSURLRequest *)request;
- (CPCurlProtocol *)protocol;
- (void *)easyHandle;

- (BOOL)isCancelled;
- (void)markCancelled;

// Main thread, after -markCancelled: drops the download owner so the two do
// not keep each other alive. The network thread checks for cancellation
// before it touches the owner.
- (void)detachDownloadOwner;

// Network thread: build and tear down the libcurl handle.
- (BOOL)prepareHandle;
- (void)releaseHandle;

// Network thread: called by the libcurl callbacks.
- (size_t)handleHeaderLine:(const char *)bytes length:(size_t)length;
- (size_t)handleBodyBytes:(const char *)bytes length:(size_t)length;
- (void)completeWithCurlCode:(int)code;

@end
