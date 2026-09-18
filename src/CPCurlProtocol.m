/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPCurlProtocol.h"
#import "CPNetworkEngine.h"
#import "CPNetworkTask.h"
#import "CPHTTPCache.h"
#import "CPDebugSnapshot.h"

@implementation CPCurlProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *scheme = [[[request URL] scheme] lowercaseString];

    // Plain http is taken over too. Tiger and Leopard try a site's IPv6
    // address first and wait about fifteen seconds for it to fail on a network
    // without IPv6, which is most home networks; libcurl tries both at once.
    // Measured on the Pismo against ftp.gnu.org: 15s through the system,
    // 0.06s over IPv4. It also brings the disk cache and compression to
    // plain-http sites.
    return [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b
{
    return [super requestIsCacheEquivalent:a toRequest:b];
}

- (void)startLoading
{
    NSCachedURLResponse *cached = [CPHTTPCache cachedResponseForRequest:[self request]];

    if (cached != nil && [CPHTTPCache cachedResponseIsFresh:cached forRequest:[self request]]) {
        if (CPDebugSnapshotPath() != nil)
            NSLog(@"Captain Polliwog: cache-hit %@", [[self request] URL]);
        // Still fresh: no connection, no handshake, no transfer. Delivered on
        // the next pass of the run loop rather than inside -startLoading.
        [self performSelector:@selector(serveCachedResponse:) withObject:cached afterDelay:0.0];
        return;
    }

    task = [[CPNetworkTask alloc] initWithRequest:[self request]
                                         protocol:self
                                   cachedResponse:cached];
    [[CPNetworkEngine sharedEngine] startTask:task];
}

- (void)serveCachedResponse:(NSCachedURLResponse *)cached
{
    if (![[cached response] respondsToSelector:@selector(allHeaderFields)]) {
        // WebKit would send -allHeaderFields to this and bring the app down.
        NSLog(@"Captain Polliwog: unusable cache entry for %@", [[self request] URL]);
        [[self client] URLProtocol:self didFailWithError:
         [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorResourceUnavailable userInfo:nil]];
        return;
    }
    [[self client] URLProtocol:self
            didReceiveResponse:[cached response]
            cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if ([[cached data] length] > 0)
        [[self client] URLProtocol:self didLoadData:[cached data]];
    [[self client] URLProtocolDidFinishLoading:self];
}

- (void)stopLoading
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (task != nil) {
        [task markCancelled];
        [[CPNetworkEngine sharedEngine] cancelTask:task];
        [task release];
        task = nil;
    }
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [task release];
    [super dealloc];
}

@end

@implementation CPHTTPURLResponse

- (id)initWithURL:(NSURL *)aURL
       statusCode:(int)aStatusCode
     headerFields:(NSDictionary *)fields
         MIMEType:(NSString *)MIMEType
    contentLength:(long long)contentLength
     textEncoding:(NSString *)encoding
 suggestedFilename:(NSString *)filename
{
    self = [super initWithURL:aURL
                     MIMEType:MIMEType
        expectedContentLength:contentLength
             textEncodingName:encoding];
    if (self == nil)
        return nil;

    responseStatusCode = aStatusCode;
    responseHeaderFields = [fields copy];
    responseSuggestedFilename = [filename copy];
    return self;
}

- (void)dealloc
{
    [responseHeaderFields release];
    [responseSuggestedFilename release];
    [super dealloc];
}

// NSURLCache archives responses when it writes them to disk, and the extra
// fields here would be lost without this.
- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self == nil)
        return nil;

    if ([coder allowsKeyedCoding]) {
        responseStatusCode = [coder decodeIntForKey:@"CPStatusCode"];
        responseHeaderFields = [[coder decodeObjectForKey:@"CPHeaderFields"] retain];
        responseSuggestedFilename = [[coder decodeObjectForKey:@"CPSuggestedFilename"] retain];
    } else {
        responseStatusCode = 0;
        [coder decodeValueOfObjCType:@encode(int) at:&responseStatusCode];
        responseHeaderFields = [[coder decodeObject] retain];
        responseSuggestedFilename = [[coder decodeObject] retain];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    if ([coder allowsKeyedCoding]) {
        [coder encodeInt:responseStatusCode forKey:@"CPStatusCode"];
        [coder encodeObject:responseHeaderFields forKey:@"CPHeaderFields"];
        [coder encodeObject:responseSuggestedFilename forKey:@"CPSuggestedFilename"];
    } else {
        [coder encodeValueOfObjCType:@encode(int) at:&responseStatusCode];
        [coder encodeObject:responseHeaderFields];
        [coder encodeObject:responseSuggestedFilename];
    }
}

- (int)statusCode
{
    return responseStatusCode;
}

- (NSDictionary *)allHeaderFields
{
    return responseHeaderFields;
}

- (NSString *)suggestedFilename
{
    if ([responseSuggestedFilename length] > 0)
        return responseSuggestedFilename;
    return [super suggestedFilename];
}

@end
