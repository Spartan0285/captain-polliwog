/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPHTTPCache.h"

#define CPHeuristicFreshnessFraction 0.1
#define CPHeuristicFreshnessCap      (24.0 * 60.0 * 60.0)

static NSString *CPHeader(NSHTTPURLResponse *response, NSString *name)
{
    NSDictionary *fields = [response allHeaderFields];
    NSEnumerator *names = [fields keyEnumerator];
    NSString *key;

    while ((key = [names nextObject]) != nil) {
        if ([key caseInsensitiveCompare:name] == NSOrderedSame)
            return [fields objectForKey:key];
    }
    return nil;
}

static BOOL CPCacheControlHas(NSString *cacheControl, NSString *directive)
{
    if (cacheControl == nil)
        return NO;
    return [[cacheControl lowercaseString] rangeOfString:directive].location != NSNotFound;
}

// Seconds from "max-age=N" or "s-maxage=N", or -1 when absent.
static double CPCacheControlMaxAge(NSString *cacheControl)
{
    NSString *lower = [cacheControl lowercaseString];
    NSRange marker = [lower rangeOfString:@"max-age="];

    if (cacheControl == nil || marker.location == NSNotFound)
        return -1.0;
    return [[lower substringFromIndex:NSMaxRange(marker)] doubleValue];
}

static NSDate *CPHeaderDate(NSHTTPURLResponse *response, NSString *name)
{
    NSString *value = CPHeader(response, name);
    NSCalendarDate *parsed;

    if ([value length] == 0)
        return nil;
    // RFC 1123, as nearly every server sends it: "Thu, 17 Sep 2026 21:59:59 GMT".
    parsed = [NSCalendarDate dateWithString:value calendarFormat:@"%a, %d %b %Y %H:%M:%S %Z"];
    if (parsed == nil)
        parsed = [NSCalendarDate dateWithString:value calendarFormat:@"%A, %d-%b-%y %H:%M:%S %Z"];
    return parsed;
}

@implementation CPHTTPCache

+ (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request
{
    NSString *method = [request HTTPMethod];

    if (method != nil && ![method isEqualToString:@"GET"])
        return nil;
    // Spelled without "Local": the longer name arrived in 10.5.
    if ([request cachePolicy] == NSURLRequestReloadIgnoringCacheData)
        return nil;
    return [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
}

+ (BOOL)cachedResponseIsFresh:(NSCachedURLResponse *)cached forRequest:(NSURLRequest *)request
{
    NSHTTPURLResponse *response;
    NSString *cacheControl;
    NSString *requestCacheControl;
    NSDate *responseDate;
    NSDate *lastModified;
    NSDate *expires;
    double maxAge;
    double age = 0.0;
    double currentAge;
    double lifetime = -1.0;

    if (cached == nil || ![[cached response] isKindOfClass:[NSHTTPURLResponse class]])
        return NO;
    response = (NSHTTPURLResponse *)[cached response];

    // An offline reader would want the stored copy whatever its age.
    if ([request cachePolicy] == NSURLRequestReturnCacheDataElseLoad ||
        [request cachePolicy] == NSURLRequestReturnCacheDataDontLoad)
        return YES;

    requestCacheControl = [request valueForHTTPHeaderField:@"Cache-Control"];
    if (CPCacheControlHas(requestCacheControl, @"no-cache") ||
        [[request valueForHTTPHeaderField:@"Pragma"] caseInsensitiveCompare:@"no-cache"] == NSOrderedSame)
        return NO;

    cacheControl = CPHeader(response, @"Cache-Control");
    if (CPCacheControlHas(cacheControl, @"no-cache") || CPCacheControlHas(cacheControl, @"no-store") ||
        CPCacheControlHas(cacheControl, @"must-revalidate"))
        return NO;

    responseDate = CPHeaderDate(response, @"Date");
    if (responseDate == nil)
        responseDate = [NSDate date];
    if (CPHeader(response, @"Age") != nil)
        age = [CPHeader(response, @"Age") doubleValue];
    currentAge = [[NSDate date] timeIntervalSinceDate:responseDate] + age;

    maxAge = CPCacheControlMaxAge(cacheControl);
    if (maxAge >= 0.0) {
        lifetime = maxAge;
    } else {
        expires = CPHeaderDate(response, @"Expires");
        if (expires != nil) {
            lifetime = [expires timeIntervalSinceDate:responseDate];
        } else {
            // No explicit lifetime: the usual heuristic of a tenth of the time
            // since the file last changed, capped at a day.
            lastModified = CPHeaderDate(response, @"Last-Modified");
            if (lastModified != nil) {
                lifetime = [responseDate timeIntervalSinceDate:lastModified] * CPHeuristicFreshnessFraction;
                if (lifetime > CPHeuristicFreshnessCap)
                    lifetime = CPHeuristicFreshnessCap;
            }
        }
    }

    return (lifetime >= 0.0 && currentAge < lifetime);
}

+ (NSDictionary *)validatorHeadersForCachedResponse:(NSCachedURLResponse *)cached
{
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSHTTPURLResponse *response;
    NSString *eTag;
    NSString *lastModified;

    if (cached == nil || ![[cached response] isKindOfClass:[NSHTTPURLResponse class]])
        return nil;
    response = (NSHTTPURLResponse *)[cached response];

    eTag = CPHeader(response, @"ETag");
    lastModified = CPHeader(response, @"Last-Modified");
    if ([eTag length] > 0)
        [headers setObject:eTag forKey:@"If-None-Match"];
    if ([lastModified length] > 0)
        [headers setObject:lastModified forKey:@"If-Modified-Since"];

    return ([headers count] > 0) ? headers : nil;
}

+ (BOOL)mayStoreResponse:(NSHTTPURLResponse *)response forRequest:(NSURLRequest *)request
{
    NSString *method = [request HTTPMethod];
    NSString *vary;

    if (method != nil && ![method isEqualToString:@"GET"])
        return NO;
    if ([response statusCode] != 200 && [response statusCode] != 301)
        return NO;
    if (CPCacheControlHas(CPHeader(response, @"Cache-Control"), @"no-store"))
        return NO;

    // Content that varies by anything except the encoding could be served back
    // to the wrong request, and matching on Vary is not worth the code here.
    vary = CPHeader(response, @"Vary");
    if ([vary length] > 0 &&
        [[vary stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
         caseInsensitiveCompare:@"Accept-Encoding"] != NSOrderedSame)
        return NO;

    return YES;
}

+ (void)storeData:(NSData *)data
         response:(NSHTTPURLResponse *)response
       forRequest:(NSURLRequest *)request
{
    NSCachedURLResponse *cached;

    if (data == nil || response == nil)
        return;
    cached = [[NSCachedURLResponse alloc] initWithResponse:response
                                                     data:data
                                                 userInfo:nil
                                            storagePolicy:NSURLCacheStorageAllowed];
    [[NSURLCache sharedURLCache] storeCachedResponse:cached forRequest:request];
    [cached release];
}

@end
