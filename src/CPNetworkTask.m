/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPNetworkTask.h"
#import "CPCurlProtocol.h"
#import "CPNetworkEngine.h"
#import "CPHTTPCache.h"
#import "CPSettings.h"
#import "CPDebugSnapshot.h"
#include <curl/curl.h>
#import "CPAccelerator.h"
#import "CPPrivateBrowsing.h"
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>

#define CPProgressInterval 0.5

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
- (void)deliverCachedResponse:(NSCachedURLResponse *)cached;
- (void)storeInCache:(NSArray *)dataAndResponse;
- (void)relayDownloadProgress:(NSArray *)receivedAndExpected;
- (void)relayDownloadFinished:(id)errorOrNull;
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

    if (viaAccelerator) {
        NSString *powerEmuError = [responseHeaders objectForKey:@"x-poweremu-error"];
        NSString *method = [request HTTPMethod];
        BOOL idempotent = method == nil || [method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"];
        if (statusCode == 401 && (powerEmuError != nil || [responseHeaders objectForKey:@"x-poweremu"] == nil)) {
            // PowerEmu itself refused us: nothing reached the site.
            [CPAccelerator markPairingRejected];
            retryDirect = YES;
            return;
        }
        if ((statusCode == 502 || statusCode == 504) && powerEmuError != nil && idempotent) {
            // PowerEmu couldn't get the page; the direct path shows the
            // site's own error if the site really is down.
            if (CPDebugLogging())
                NSLog(@"Captain Polliwog: PowerEmu error (%@) for %@; trying directly", powerEmuError, [request URL]);
            retryDirect = YES;
            return;
        }
        if (CPDebugLogging()) {
            NSString *converted = [responseHeaders objectForKey:@"x-poweremu-converted"];
            NSString *blocked = [responseHeaders objectForKey:@"x-poweremu-blocked"];
            if (converted != nil || blocked != nil)
                NSLog(@"Captain Polliwog: PowerEmu %@%@ %@", converted != nil ? @"converted " : @"blocked by ",
                      converted != nil ? converted : blocked, [request URL]);
        }
    }

    for (index = 0; index + 1 < [responseHeaderOrder count]; index += 2) {
        if ([[[responseHeaderOrder objectAtIndex:index] lowercaseString] isEqualToString:@"set-cookie"])
            [setCookieValues addObject:[responseHeaderOrder objectAtIndex:index + 1]];
    }
    if ([setCookieValues count] > 0)
        [self callOnMainThread:@selector(storeCookiesFromHeaders:) withObject:setCookieValues];

    // libcurl follows a download's redirects itself; only the final answer
    // matters, and only for its size.
    if (downloadOwner != nil) {
        long long offset = 0;
        if (resumeOffset > 0) {
            NSString *range = [responseHeaders objectForKey:@"content-range"];
            if (CPDebugLogging())
                NSLog(@"Captain Polliwog: resuming download at %lld bytes: HTTP %d", resumeOffset, statusCode);
            if (statusCode == 206) {
                offset = resumeOffset;
            } else if (statusCode == 416 && range != nil &&
                       [range rangeOfString:@"/"].location != NSNotFound &&
                       strtoll([[range substringFromIndex:[range rangeOfString:@"/"].location + 1] UTF8String], NULL, 10) == resumeOffset) {
                // Asked for the bytes after the end: the file was already whole.
                rangeComplete = YES;
                bytesExpected = resumeOffset;
                return;
            } else if (statusCode >= 200 && statusCode <= 299 && downloadFile != NULL) {
                // The whole file is coming again: start it over.
                fflush(downloadFile);
                ftruncate(fileno(downloadFile), 0);
                fseeko(downloadFile, 0, SEEK_SET);
                bytesWritten = 0;
                resumeOffset = 0;
            }
        }
        if (statusCode >= 200 && statusCode <= 299 && [responseHeaders objectForKey:@"content-length"] != nil &&
            [responseHeaders objectForKey:@"content-encoding"] == nil)
            bytesExpected = offset + strtoll([[responseHeaders objectForKey:@"content-length"] UTF8String], NULL, 10);
        return;
    }

    if (statusCode == 304 && cachedResponse != nil) {
        // Not modified: the stored copy stands, and only headers came over
        // the wire. This is the cheap path we want as often as possible.
        servedFromCache = YES;
        if (CPDebugLogging())
            NSLog(@"Captain Polliwog: revalidated %@", [request URL]);
        [self callOnMainThread:@selector(deliverCachedResponse:) withObject:cachedResponse];
        return;
    }

    if (statusCode >= 301 && statusCode <= 308 && statusCode != 304 && statusCode != 305 &&
        [responseHeaders objectForKey:@"location"] != nil) {
        // Redirects go back to WebKit rather than being followed here, so the
        // address bar, cookies and page security all stay in WebKit's hands.
        // -absoluteURL matters: a relative Location ("/cookies") otherwise
        // stays a URL-with-a-base, and WebKit drops the base and goes to
        // file:///cookies.
        NSURL *target = [[NSURL URLWithString:[responseHeaders objectForKey:@"location"]
                                 relativeToURL:[request URL]] absoluteURL];
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
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: from-network(%d) %@", statusCode, [request URL]);
    [lastResponse release];
    lastResponse = [[self buildResponse] retain];
    if ([CPHTTPCache mayStoreResponse:lastResponse forRequest:request]) {
        [cacheData release];
        cacheData = [[NSMutableData alloc] init];
    }
    [self callOnMainThread:@selector(deliverResponse:) withObject:lastResponse];
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
        // -longLongValue on NSString is 10.5 and later.
        length = strtoll([lengthText UTF8String], NULL, 10);

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

- (void)deliverCachedResponse:(NSCachedURLResponse *)cached
{
    CPCurlProtocol *finishing = protocol;

    if (cancelled || finishing == nil)
        return;
    protocol = nil;
    [[finishing client] URLProtocol:finishing
                didReceiveResponse:[cached response]
                cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if ([[cached data] length] > 0)
        [[finishing client] URLProtocol:finishing didLoadData:[cached data]];
    [[finishing client] URLProtocolDidFinishLoading:finishing];
    [finishing release];
}

- (void)relayDownloadProgress:(NSArray *)receivedAndExpected
{
    if (!cancelled)
        [downloadOwner downloadReceivedBytes:receivedAndExpected];
}

- (void)relayDownloadFinished:(id)errorOrNull
{
    id owner = downloadOwner;
    if (cancelled || owner == nil)
        return;
    downloadOwner = nil;
    [owner downloadFinishedWithError:(errorOrNull == [NSNull null] ? nil : errorOrNull)];
    [owner release];
}

- (void)storeInCache:(NSArray *)dataAndResponse
{
    [CPHTTPCache storeData:[dataAndResponse objectAtIndex:0]
                  response:[dataAndResponse objectAtIndex:1]
                forRequest:request];
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

// The Accept-Language header the system's networking would add, which this
// networking replaces: the user's preferred languages, most preferred first
// ("en-us, fr;q=0.9"). Sites treat a request without one as a script, not a
// browser: eBay answers a search with an error page.
static NSString *CPAcceptLanguageHeader(void)
{
    static NSString *header = nil;
    NSArray *languages;
    NSMutableArray *parts;
    unsigned index;

    if (header != nil)
        return header;
    languages = [[NSUserDefaults standardUserDefaults] arrayForKey:@"AppleLanguages"];
    parts = [NSMutableArray array];
    for (index = 0; index < [languages count] && [parts count] < 4; index++) {
        NSMutableString *language = [NSMutableString stringWithString:[[languages objectAtIndex:index] lowercaseString]];
        [language replaceOccurrencesOfString:@"_" withString:@"-" options:0 range:NSMakeRange(0, [language length])];
        // Mac OS X lists English as "en"; Safari sent "en-us".
        if ([language isEqualToString:@"en"])
            [language setString:@"en-us"];
        if ([language length] == 0 || [parts containsObject:language])
            continue;
        if ([parts count] == 0)
            [parts addObject:language];
        else
            [parts addObject:[NSString stringWithFormat:@"%@;q=0.%u", language, 10 - (unsigned)[parts count]]];
    }
    if ([parts count] == 0)
        [parts addObject:@"en-us"];
    header = [[parts componentsJoinedByString:@", "] retain];
    return header;
}

@implementation CPNetworkTask

- (id)initWithRequest:(NSURLRequest *)aRequest
             protocol:(CPCurlProtocol *)aProtocol
       cachedResponse:(NSCachedURLResponse *)aCachedResponse
{
    self = [super init];
    if (self == nil)
        return nil;

    request = [aRequest retain];
    protocol = [aProtocol retain];
    cachedResponse = [aCachedResponse retain];
    responseHeaders = [[NSMutableDictionary alloc] init];
    responseHeaderOrder = [[NSMutableArray alloc] init];
    statusCode = 0;
    return self;
}

- (id)initWithRequest:(NSURLRequest *)aRequest downloadPath:(NSString *)path owner:(id)owner
{
    return [self initWithRequest:aRequest downloadPath:path resume:NO owner:owner];
}

- (id)initWithRequest:(NSURLRequest *)aRequest downloadPath:(NSString *)path
               resume:(BOOL)resume owner:(id)owner
{
    self = [super init];
    if (self == nil)
        return nil;

    request = [aRequest retain];
    downloadOwner = [owner retain];
    responseHeaders = [[NSMutableDictionary alloc] init];
    responseHeaderOrder = [[NSMutableArray alloc] init];
    downloadFile = resume ? fopen([path fileSystemRepresentation], "r+b") : NULL;
    if (downloadFile != NULL && fseeko(downloadFile, 0, SEEK_END) == 0) {
        resumeOffset = ftello(downloadFile);
        bytesWritten = resumeOffset;
    } else {
        if (downloadFile != NULL)
            fclose(downloadFile);
        downloadFile = fopen([path fileSystemRepresentation], "wb");
    }
    if (downloadFile == NULL) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc
{
    [downloadOwner release];
    [self releaseHandle];
    [request release];
    [protocol release];
    [uploadBody release];
    [cachedResponse release];
    [lastResponse release];
    [cacheData release];
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

- (void)detachDownloadOwner
{
    [downloadOwner release];
    downloadOwner = nil;
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
    viaAccelerator = !bypassAccelerator && [CPAccelerator shouldRoute:[request URL]];
    if (viaAccelerator) {
        // To PowerEmu, asking for the real URL (an absolute-form request
        // target, as to a forward proxy); PowerEmu makes the TLS connection.
        NSURL *url = [request URL];
        NSString *target = [url absoluteString];
        NSString *host = [url host];
        NSRange fragment = [target rangeOfString:@"#"];
        if (fragment.location != NSNotFound)
            target = [target substringToIndex:fragment.location];
        if ([url port] != nil)
            host = [NSString stringWithFormat:@"%@:%@", host, [url port]];
        curl_easy_setopt(easy, CURLOPT_URL, [[CPAccelerator baseURL] UTF8String]);
        curl_easy_setopt(easy, CURLOPT_REQUEST_TARGET, [target UTF8String]);
        headers = curl_slist_append(headers, [[@"Host: " stringByAppendingString:host] UTF8String]);
        headers = curl_slist_append(headers, [[@"X-PowerEmu-Engine: " stringByAppendingString:[CPAccelerator engineHeader]] UTF8String]);
        if ([CPAccelerator token] != nil)
            headers = curl_slist_append(headers, [[@"X-PowerEmu-Token: " stringByAppendingString:[CPAccelerator token]] UTF8String]);
        if ([[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled])
            headers = curl_slist_append(headers, "X-PowerEmu-Private: 1");
    } else {
        curl_easy_setopt(easy, CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);
    }
    curl_easy_setopt(easy, CURLOPT_ERRORBUFFER, errorBuffer);
    curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
    // A page's redirects go back to WebKit; a download has no WebKit to go
    // back to, so libcurl follows them itself.
    curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, (downloadOwner != nil) ? 1L : 0L);
    curl_easy_setopt(easy, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(easy, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_1_1);
    // Compression is a clear win here: these machines wait on the network far
    // longer than they spend unpacking gzip.
    // ...but not when resuming: a range of compressed bytes can't be joined
    // to the ones already saved.
    // CURLOPT_RANGE rather than RESUME_FROM, which fails outright when the
    // server sends the whole file instead.
    if (resumeOffset > 0) {
        char range[32];
        snprintf(range, sizeof range, "%lld-", resumeOffset);
        curl_easy_setopt(easy, CURLOPT_RANGE, range);
    } else
        curl_easy_setopt(easy, CURLOPT_ACCEPT_ENCODING, "");
    curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, CPHeaderCallback);
    curl_easy_setopt(easy, CURLOPT_HEADERDATA, self);
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, CPWriteCallback);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, self);
    if (viaAccelerator)
        curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT_MS, 1500L);
    else
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
    if ([request valueForHTTPHeaderField:@"Accept-Language"] == nil)
        headers = curl_slist_append(headers, [[NSString stringWithFormat:@"Accept-Language: %@",
                                               CPAcceptLanguageHeader()] UTF8String]);

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
    // Revalidate rather than re-download when a stale copy has validators.
    if (cachedResponse != nil) {
        NSDictionary *validators = [CPHTTPCache validatorHeadersForCachedResponse:cachedResponse];
        NSEnumerator *validatorNames = [validators keyEnumerator];
        NSString *validatorName;
        while ((validatorName = [validatorNames nextObject]) != nil)
            headers = curl_slist_append(headers,
                                        [[NSString stringWithFormat:@"%@: %@", validatorName,
                                          [validators objectForKey:validatorName]] UTF8String]);
    }
    headers = curl_slist_append(headers, "Expect:");
    headerList = headers;
    curl_easy_setopt(easy, CURLOPT_HTTPHEADER, headers);

    if (method == nil)
        method = @"GET";
    if (uploadBody == nil)
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

- (BOOL)takeDirectRetry
{
    if (!retryDirect || cancelled)
        return NO;
    retryDirect = NO;
    bypassAccelerator = YES;
    viaAccelerator = NO;
    statusCode = 0;
    [responseHeaders removeAllObjects];
    [responseHeaderOrder removeAllObjects];
    return YES;     // keeps uploadBody: a body stream can only be read once
}

- (void)releaseHandle
{
    if (downloadFile != NULL) {
        fclose(downloadFile);
        downloadFile = NULL;
    }
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
    if (retryDirect)
        return length;      // PowerEmu's error page: the retry will answer
    if (downloadOwner != nil) {
        double now;
        // Error pages are not what the reader asked to save.
        if (statusCode >= 400)
            return length;
        if (downloadFile == NULL || fwrite(bytes, 1, length, downloadFile) != length)
            return 0;       // disk full or gone: abort the transfer
        bytesWritten += length;
        // Progress at most twice a second: redrawing is not free on a G3.
        now = CFAbsoluteTimeGetCurrent();
        if (now - lastProgressReport >= CPProgressInterval) {
            lastProgressReport = now;
            [self callOnMainThread:@selector(relayDownloadProgress:)
                        withObject:[NSArray arrayWithObjects:
                                    [NSNumber numberWithLongLong:bytesWritten],
                                    [NSNumber numberWithLongLong:bytesExpected], nil]];
        }
        return length;
    }
    if (redirectLocation != nil || servedFromCache)
        return length;      // nothing here belongs to the page
    if (cacheData != nil && length > 0) {
        if ([cacheData length] + length > [[CPSettings sharedSettings] maximumCachedResponseBytes]) {
            // Too big to hold: stream it and give up on caching this one.
            [cacheData release];
            cacheData = nil;
        } else {
            [cacheData appendBytes:bytes length:length];
        }
    }
    if (length > 0)
        [self callOnMainThread:@selector(deliverData:)
                    withObject:[NSData dataWithBytes:bytes length:length]];
    return length;
}

- (void)completeWithCurlCode:(int)code
{
    if (cancelled || servedFromCache)
        return;
    if (viaAccelerator && !retryDirect && code != CURLE_OK && statusCode == 0) {
        double connectTime = 0;
        NSString *method = [request HTTPMethod];
        BOOL idempotent = method == nil || [method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"];
        curl_easy_getinfo((CURL *)easyHandle, CURLINFO_CONNECT_TIME, &connectTime);
        if (connectTime <= 0) {
            // Never reached PowerEmu, so nothing reached the site: safe to
            // send again directly, whatever the method.
            [CPAccelerator markFailed];
            retryDirect = YES;
        } else if (idempotent && (code == CURLE_GOT_NOTHING || code == CURLE_RECV_ERROR || code == CURLE_SEND_ERROR)) {
            retryDirect = YES;
        }
    }
    if (retryDirect)
        return;             // the engine starts it again, directly
    if (downloadOwner != nil) {
        NSError *error = nil;
        if (downloadFile != NULL) {
            fclose(downloadFile);
            downloadFile = NULL;
        }
        if (code != CURLE_OK) {
            error = [self errorForCurlCode:code];
        } else if (statusCode >= 400 && !rangeComplete) {
            error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse
                                    userInfo:[NSDictionary dictionaryWithObject:
                                              [NSString stringWithFormat:@"The server answered with error %d.", statusCode]
                                                                         forKey:NSLocalizedDescriptionKey]];
        }
        [self callOnMainThread:@selector(relayDownloadProgress:)
                    withObject:[NSArray arrayWithObjects:
                                [NSNumber numberWithLongLong:bytesWritten],
                                [NSNumber numberWithLongLong:bytesExpected], nil]];
        [self callOnMainThread:@selector(relayDownloadFinished:)
                    withObject:(error != nil ? (id)error : (id)[NSNull null])];
        return;
    }
    if (code != CURLE_OK) {
        [self callOnMainThread:@selector(deliverError:) withObject:[self errorForCurlCode:code]];
        return;
    }
    if (redirectLocation != nil)
        return;             // WebKit is already starting the new request
    if (cacheData != nil && lastResponse != nil)
        [self callOnMainThread:@selector(storeInCache:)
                    withObject:[NSArray arrayWithObjects:cacheData, lastResponse, nil]];
    if (!responseDelivered) {
        responseDelivered = YES;
        [self callOnMainThread:@selector(deliverResponse:) withObject:[self buildResponse]];
    }
    [self callOnMainThread:@selector(deliverFinish) withObject:nil];
}

@end
