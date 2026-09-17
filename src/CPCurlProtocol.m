/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPCurlProtocol.h"
#import "CPNetworkEngine.h"
#import "CPNetworkTask.h"

@implementation CPCurlProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    // Only https is taken over. Plain http already works through the system,
    // and leaving it alone keeps the change small.
    return [[[[request URL] scheme] lowercaseString] isEqualToString:@"https"];
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
    task = [[CPNetworkTask alloc] initWithRequest:[self request] protocol:self];
    [[CPNetworkEngine sharedEngine] startTask:task];
}

- (void)stopLoading
{
    if (task != nil) {
        [task markCancelled];
        [[CPNetworkEngine sharedEngine] cancelTask:task];
        [task release];
        task = nil;
    }
}

- (void)dealloc
{
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
