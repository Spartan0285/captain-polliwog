/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPNetworkTask.h"
#import "CPCurlProtocol.h"
#import "CPNetworkEngine.h"
#include <curl/curl.h>

static NSString *CPTrimmed(NSString *text)
{
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static size_t CPHeaderCallback(char *buffer, size_t size, size_t count, void *userData)
{
    return [(CPNetworkTask *)userData handleHeaderLine:buffer length:(size * count)];
}

static size_t CPWriteCallback(char *buffer, size_t size, size_t count, void *userData)
{
    return [(CPNetworkTask *)userData handleBodyBytes:buffer length:(size * count)];
}

@interface CPNetworkTask (Private)
- (void)headersComplete;
- (NSDictionary *)combinedHeaderFields;
- (CPHTTPURLResponse *)buildResponse;
- (NSError *)errorForCurlCode:(int)code;
- (void)deliverResponse:(CPHTTPURLResponse *)response;
- (void)deliverData:(NSData *)data;
- (void)deliverRedirect:(NSArray *)requestAndResponse;
- (void)deliverFinish;
- (void)deliverError:(NSError *)error;
- (void)storeCookiesFromHeaders:(NSArray *)setCookieValues;
- (void)callOnMainThread:(SEL)selector withObject:(id)object;
@end

@implementation CPNetworkTask (Private)

// Called on the network thread once a complete header block has arrived.
- (void)headersComplete
{
    NSMutableArray *setCookieValues = [NSMutableArray array];
    unsigned index;

    if (statusCode >= 100 && statusCode <= 199)
        return;             // keep waiting for the real response

    for (index = 0; index + 1 < [responseHeaderOrder count]; index += 2) {
        if ([[[responseHeaderOrder objectAtIndex:index] lowercaseString] isEqualToString:@"set-cookie"])
            [setCookieValues addObject:[responseHeaderOrder objectAtIndex:index + 1]];
    }
    if ([setCookieValues count] > 0)
        [self callOnMainThread:@selector(storeCookiesFromHeaders:) withObject:setCookieValues];

    if (statusCode >= 301 && statusCode <= 308 && statusCode != 304 && statusCode != 305 &&
        [responseHeaders objectForKey:@"location"] != nil) {
        // Redirects go back to WebKit rather than being followed here, so the
        // address bar, cookies and page security all stay in WebKit's hands.
        NSURL *target = [NSURL URLWithString:[responseHeaders objectForKey:@"location"]
                                relativeToURL:[request URL]];
        if (target != nil) {
            NSMutableURLRequest *next = [[request mutableCopy] autorelease];
            [next setURL:target];
            if (statusCode == 303 ||
                ((statusCode == 301 || statusCode == 302) &&
                 ![[request HTTPMethod] isEqualToString:@"GET"] &&
                 ![[request HTTPMethod] isEqualToString:@"HEAD"])) {
                [next setHTTPMethod:@"GET"];
                [next setHTTPBody:nil];
            }
            [redirectLocation release];
            redirectLocation = [[target absoluteString] copy];
            [self callOnMainThread:@selector(deliverRedirect:)
                        withObject:[NSArray arrayWithObjects:next, [self buildResponse], nil]];
            return;
        }
    }

    responseDelivered = YES;
    [self callOnMainThread:@selector(deliverResponse:) withObject:[self buildResponse]];
}

- (NSDictionary *)combinedHeaderFields
{
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    unsigned index;

    for (index = 0; index + 1 < [responseHeaderOrder count]; index += 2) {
        NSString *name = [responseHeaderOrder objectAtIndex:index];
        NSString *value = [responseHeaderOrder objectAtIndex:index + 1];
        NSString *existing = [fields objectForKey:name];
        if (existing != nil)
            value = [existing stringByAppendingFormat:@", %@", value];
        [fields setObject:value forKey:name];
    }
    return fields;
}

- (CPHTTPURLResponse *)buildResponse
{
    NSString *contentType = [responseHeaders objectForKey:@"content-type"];
    NSString *disposition = [responseHeaders objectForKey:@"content-disposition"];
    NSString *lengthText = [responseHeaders objectForKey:@"content-length"];
    NSString *MIMEType = nil;
    NSString *encoding = nil;
    NSString *filename = nil;
    long long length = -1;

    if (contentType != nil) {
        NSArray *parts = [contentType componentsSeparatedByString:@";"];
        unsigned index;
        MIMEType = [CPTrimmed([parts objectAtIndex:0]) lowercaseString];
        for (index = 1; index < [parts count]; index++) {
            NSString *parameter = CPTrimmed([parts objectAtIndex:index]);
            if ([[parameter lowercaseString] hasPrefix:@"charset="]) {
                encoding = CPTrimmed([parameter substringFromIndex:8]);
                encoding = [encoding stringByTrimmingCharactersInSet:
                            [NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
            }
        }
    }
    if ([MIMEType length] == 0)
        MIMEType = @"application/octet-stream";

    // Content-Length is the encoded size; with gzip in play it would mislead
    // WebKit's progress, so only trust it when nothing was re-encoded.
    if (lengthText != nil && [responseHeaders objectForKey:@"content-encoding"] == nil)
        length = [lengthText longLongValue];

    if (disposition != nil) {
        NSRange marker = [[disposition lowercaseString] rangeOfString:@"filename="];
        if (marker.location != NSNotFound) {
            NSString *rest = CPTrimmed([disposition substringFromIndex:NSMaxRange(marker)]);
            rest = [[rest componentsSeparatedByString:@";"] objectAtIndex:0];
            filename = [CPTrimmed(rest) stringByTrimmingCharactersInSet:
                        [NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
            filename = [filename lastPathComponent];
        }
    }

    return [[[CPHTTPURLResponse alloc] initWithURL:[request URL]
                                        statusCode:statusCode
                                      headerFields:[self combinedHeaderFields]
                                          MIMEType:MIMEType
                                     contentLength:length
                                      textEncoding:encoding
                                 suggestedFilename:filename] autorelease];
}

- (NSError *)errorForCurlCode:(int)code
{
    int cocoaCode = NSURLErrorUnknown;
    NSString *detail = nil;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];

    switch (code) {
    case CURLE_UNSUPPORTED_PROTOCOL:    cocoaCode = NSURLErrorUnsupportedURL; break;
    case CURLE_URL_MALFORMAT:           cocoaCode = NSURLErrorBadURL; break;
    case CURLE_COULDNT_RESOLVE_PROXY:   cocoaCode = NSURLErrorCannotFindHost; break;
    case CURLE_COULDNT_RESOLVE_HOST:    cocoaCode = NSURLErrorCannotFindHost; break;
    case CURLE_COULDNT_CONNECT:         cocoaCode = NSURLErrorCannotConnectToHost; break;
    case CURLE_OPERATION_TIMEDOUT:      cocoaCode = NSURLErrorTimedOut; break;
    case CURLE_TOO_MANY_REDIRECTS:      cocoaCode = NSURLErrorHTTPTooManyRedirects; break;
    case CURLE_GOT_NOTHING:             cocoaCode = NSURLErrorBadServerResponse; break;
    case CURLE_SEND_ERROR:              cocoaCode = NSURLErrorNetworkConnectionLost; break;
    case CURLE_RECV_ERROR:              cocoaCode = NSURLErrorNetworkConnectionLost; break;
    case CURLE_ABORTED_BY_CALLBACK:     cocoaCode = NSURLErrorCancelled; break;
    case CURLE_SSL_CONNECT_ERROR:       cocoaCode = NSURLErrorSecureConnectionFailed; break;
    case CURLE_SSL_CIPHER:              cocoaCode = NSURLErrorSecureConnectionFailed; break;
    case CURLE_SSL_ENGINE_NOTFOUND:     cocoaCode = NSURLErrorSecureConnectionFailed; break;
    case CURLE_PEER_FAILED_VERIFICATION: cocoaCode = NSURLErrorServerCertificateUntrusted; break;
    case CURLE_SSL_ISSUER_ERROR:        cocoaCode = NSURLErrorServerCertificateUntrusted; break;
    default:                            cocoaCode = NSURLErrorUnknown; break;
    }

    if (errorBuffer != NULL && errorBuffer[0] != '\0')
        detail = [NSString stringWithUTF8String:errorBuffer];
    if ([detail length] == 0)
        detail = [NSString stringWithUTF8String:curl_easy_strerror((CURLcode)code)];

    [info setObject:detail forKey:NSLocalizedDescriptionKey];
    [info setObject:[[request URL] absoluteString] forKey:@"NSErrorFailingURLStringKey"];
    [info setObject:[request URL] forKey:@"NSErrorFailingURLKey"];
    return [NSError errorWithDomain:NSURLErrorDomain code:cocoaCode userInfo:info];
}

#pragma mark Main thread

- (void)callOnMainThread:(SEL)selector withObject:(id)object
{
    [self performSelectorOnMainThread:selector withObject:object waitUntilDone:NO];
}

- (void)deliverResponse:(CPHTTPURLResponse *)response
{
    if (cancelled || protocol == nil)
        return;
    [[protocol client] URLProtocol:protocol
               didReceiveResponse:response
               cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)deliverData:(NSData *)data
{
    if (cancelled || protocol == nil)
        return;
    [[protocol client] URLProtocol:protocol didLoadData:data];
}

- (void)deliverRedirect:(NSArray *)requestAndResponse
{
    if (cancelled || protocol == nil)
        return;
    [[protocol client] URLProtocol:protocol
         wasRedirectedToRequest:[requestAndResponse objectAtIndex:0]
               redirectResponse:[requestAndResponse objectAtIndex:1]];
}

- (void)deliverFinish
{
    CPCurlProtocol *finishing = protocol;
    if (cancelled || finishing == nil)
        return;
    protocol = nil;
    [[finishing client] URLProtocolDidFinishLoading:finishing];
    [finishing release];
}

- (void)deliverError:(NSError *)error
{
    CPCurlProtocol *failing = protocol;
    if (cancelled || failing == nil)
        return;
    protocol = nil;
    [[failing client] URLProtocol:failing didFailWithError:error];
    [failing release];
}

- (void)storeCookiesFromHeaders:(NSArray *)setCookieValues
{
    NSDictionary *fields = [NSDictionary dictionaryWithObject:
                            [setCookieValues componentsJoinedByString:@", "]
                                                       forKey:@"Set-Cookie"];
    NSArray *cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:fields forURL:[request URL]];

    if ([cookies count] > 0)
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cookies
                                                          forURL:[request URL]
                                                 mainDocumentURL:[request mainDocumentURL]];
}

@end

@implementation CPNetworkTask

- (id)initWithRequest:(NSURLRequest *)aRequest protocol:(CPCurlProtocol *)aProtocol
{
    self = [super init];
    if (self == nil)
        return nil;

    request = [aRequest retain];
    protocol = [aProtocol retain];
    responseHeaders = [[NSMutableDictionary alloc] init];
    responseHeaderOrder = [[NSMutableArray alloc] init];
    statusCode = 0;
    return self;
}

- (void)dealloc
{
    [self releaseHandle];
    [request release];
    [protocol release];
    [uploadBody release];
    [responseHeaders release];
    [responseHeaderOrder release];
    [httpVersion release];
    [redirectLocation release];
    [super dealloc];
}

- (NSURLRequest *)request
{
    return request;
}

- (CPCurlProtocol *)protocol
{
    return protocol;
}

- (void *)easyHandle
{
    return easyHandle;
}

- (BOOL)isCancelled
{
    return cancelled;
}

- (void)markCancelled
{
    cancelled = YES;
}

#pragma mark Network thread

- (BOOL)prepareHandle
{
    CURL *easy = curl_easy_init();
    NSDictionary *headerFields = [request allHTTPHeaderFields];
    NSEnumerator *names = [headerFields keyEnumerator];
    NSString *name;
    NSString *method = [request HTTPMethod];
    NSArray *cookies;
    struct curl_slist *headers = NULL;
    NSString *caBundle = [CPNetworkEngine certificateBundlePath];

    if (easy == NULL)
        return NO;
    easyHandle = easy;
    errorBuffer = calloc(1, CURL_ERROR_SIZE);

    curl_easy_setopt(easy, CURLOPT_PRIVATE, self);
    curl_easy_setopt(easy, CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);
    curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, errorBuffer);
    curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(easy, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_1_1);
    // Compression is a clear win here: these machines wait on the network far
    // longer than they spend unpacking gzip.
    curl_easy_setopt(easy, CURLOPT_ACCEPT_ENCODING, "");
    curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, CPHeaderCallback);
    curl_easy_setopt(easy, CURLOPT_HEADERDATA, self);
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, CPWriteCallback);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, self);
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT, 30L);
    curl_easy_setopt(easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(easy, CURLOPT_LOW_SPEED_TIME, 120L);

    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(easy, CURLOPT_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_2);
    if (caBundle != nil)
        curl_easy_setopt(easy, CURLOPT_CAINFO, [caBundle fileSystemRepresentation]);

    while ((name = [names nextObject]) != nil) {
        NSString *line = [NSString stringWithFormat:@"%@: %@", name,
                          [headerFields objectForKey:name]];
        headers = curl_slist_append(headers, [line UTF8String]);
    }

    // WebKit leaves cookies to the URL loading system, which we have replaced,
    // so they have to be attached and stored here or logins never stick.
    cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[request URL]];
    if ([cookies count] > 0 && [headerFields objectForKey:@"Cookie"] == nil) {
        NSDictionary *cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        NSString *cookieHeader = [cookieHeaders objectForKey:@"Cookie"];
        if ([cookieHeader length] > 0)
            headers = curl_slist_append(headers,
                                        [[NSString stringWithFormat:@"Cookie: %@", cookieHeader] UTF8String]);
    }
    headers = curl_slist_append(headers, "Expect:");
    headerList = headers;
    curl_easy_setopt(easy, CURLOPT_HTTPHEADER, headers);

    if (method == nil)
        method = @"GET";
    uploadBody = [[request HTTPBody] retain];
    if (uploadBody == nil && [request HTTPBodyStream] != nil) {
        NSMutableData *collected = [NSMutableData data];
        NSInputStream *stream = [request HTTPBodyStream];
        uint8_t buffer[8192];
        int read;
        [stream open];
        while ((read = [stream read:buffer maxLength:sizeof(buffer)]) > 0)
            [collected appendBytes:buffer length:read];
        [stream close];
        uploadBody = [collected retain];
    }

    if ([method isEqualToString:@"HEAD"]) {
        curl_easy_setopt(easy, CURLOPT_NOBODY, 1L);
    } else if (uploadBody != nil) {
        curl_easy_setopt(easy, CURLOPT_POSTFIELDS, [uploadBody bytes]);
        curl_easy_setopt(easy, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)[uploadBody length]);
        if (![method isEqualToString:@"POST"])
            curl_easy_setopt(easy, CURLOPT_CUSTOMREQUEST, [method UTF8String]);
    } else if (![method isEqualToString:@"GET"]) {
        curl_easy_setopt(easy, CURLOPT_CUSTOMREQUEST, [method UTF8String]);
    }

    return YES;
}

- (void)releaseHandle
{
    if (easyHandle != NULL) {
        curl_easy_cleanup((CURL *)easyHandle);
        easyHandle = NULL;
    }
    if (headerList != NULL) {
        curl_slist_free_all((struct curl_slist *)headerList);
        headerList = NULL;
    }
    if (errorBuffer != NULL) {
        free(errorBuffer);
        errorBuffer = NULL;
    }
}

- (size_t)handleHeaderLine:(const char *)bytes length:(size_t)length
{
    NSString *line = [[[NSString alloc] initWithBytes:bytes length:length
                                             encoding:NSISOLatin1StringEncoding] autorelease];
    NSString *trimmed = CPTrimmed(line);
    NSRange colon;

    if (cancelled)
        return 0;

    if ([trimmed hasPrefix:@"HTTP/"]) {
        NSArray *parts = [trimmed componentsSeparatedByString:@" "];
        [responseHeaders removeAllObjects];
        [responseHeaderOrder removeAllObjects];
        [httpVersion release];
        httpVersion = [[parts objectAtIndex:0] copy];
        statusCode = ([parts count] > 1) ? [[parts objectAtIndex:1] intValue] : 0;
        return length;
    }

    if ([trimmed length] == 0) {
        [self headersComplete];
        return length;
    }

    colon = [trimmed rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        NSString *name = CPTrimmed([trimmed substringToIndex:colon.location]);
        NSString *value = CPTrimmed([trimmed substringFromIndex:NSMaxRange(colon)]);
        [responseHeaders setObject:value forKey:[name lowercaseString]];
        [responseHeaderOrder addObject:name];
        [responseHeaderOrder addObject:value];
    }
    return length;
}

- (size_t)handleBodyBytes:(const char *)bytes length:(size_t)length
{
    if (cancelled)
        return 0;
    if (redirectLocation != nil)
        return length;      // discard a redirect's body
    if (length > 0)
        [self callOnMainThread:@selector(deliverData:)
                    withObject:[NSData dataWithBytes:bytes length:length]];
    return length;
}

- (void)completeWithCurlCode:(int)code
{
    if (cancelled)
        return;
    if (code != CURLE_OK) {
        [self callOnMainThread:@selector(deliverError:) withObject:[self errorForCurlCode:code]];
        return;
    }
    if (redirectLocation != nil)
        return;             // WebKit is already starting the new request
    if (!responseDelivered) {
        responseDelivered = YES;
        [self callOnMainThread:@selector(deliverResponse:) withObject:[self buildResponse]];
    }
    [self callOnMainThread:@selector(deliverFinish) withObject:nil];
}

@end
