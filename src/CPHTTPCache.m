/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPHTTPCache.h"
#import "CPCurlProtocol.h"
#import "CPPrivateBrowsing.h"
#include <string.h>

// Storage is two plain files per entry rather than NSURLCache. Leopard's
// NSURLCache crashes inside CFNetwork when it reads back anything but its own
// entries -- a custom response subclass and a userInfo dictionary each brought
// the app down -- and files also mean no SQLite work on a 500MHz G3, with the
// size on disk being simply the size of the folder.
#define CPHeuristicFreshnessFraction 0.1
#define CPHeuristicFreshnessCap      (24.0 * 60.0 * 60.0)

static NSString * const CPMetaURL      = @"url";
static NSString * const CPMetaStatus   = @"status";
static NSString * const CPMetaHeaders  = @"headers";
static NSString * const CPMetaMIMEType = @"mime";
static NSString * const CPMetaEncoding = @"encoding";
static NSString * const CPMetaLength   = @"length";
static NSString * const CPMetaVary     = @"vary";   // request headers that matter

static NSString            *CPCacheRoot = nil;
static unsigned             CPDiskCapacity = 0;
static unsigned             CPMemoryCapacity = 0;
static NSMutableDictionary *CPMemoryEntries = nil;  // key -> NSCachedURLResponse
static NSMutableArray      *CPMemoryOrder = nil;    // keys, least recent first
static unsigned             CPMemoryBytes = 0;

static void CPLog(NSString *format, ...)
{
    va_list arguments;

    if ([[NSUserDefaults standardUserDefaults] stringForKey:@"CPDebugSnapshotPath"] == nil)
        return;
    va_start(arguments, format);
    NSLogv([@"Captain Polliwog: " stringByAppendingString:format], arguments);
    va_end(arguments);
}

// -createDirectoryAtPath:withIntermediateDirectories: is 10.5 and later, and
// the 10.4 call fails outright when a parent is missing.
static void CPCreateDirectories(NSString *path)
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSArray *components = [path pathComponents];
    NSString *partial = @"";
    unsigned index;

    for (index = 0; index < [components count]; index++) {
        partial = [partial stringByAppendingPathComponent:[components objectAtIndex:index]];
        if (![files fileExistsAtPath:partial])
            [files createDirectoryAtPath:partial attributes:nil];
    }
}

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

// CommonCrypto arrived in 10.5, so the file name is an FNV-1a hash of the URL
// computed here. Two URLs could in principle land on the same name, so the URL
// is stored in the entry and checked when it is read back.
static NSString *CPCacheKeyForRequest(NSURLRequest *request)
{
    const char *text = [[[request URL] absoluteString] UTF8String];
    unsigned long long hash = 14695981039346656037ULL;
    size_t index;
    size_t length;

    if (text == NULL)
        return nil;
    length = strlen(text);
    for (index = 0; index < length; index++) {
        hash ^= (unsigned long long)(unsigned char)text[index];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx%08lx", hash, (unsigned long)length];
}

static NSString *CPEntryPath(NSString *key, NSString *extension)
{
    if (CPCacheRoot == nil || [key length] < 2)
        return nil;
    // One level of fan-out keeps each directory small enough to list quickly.
    return [[CPCacheRoot stringByAppendingPathComponent:[key substringToIndex:2]]
            stringByAppendingPathComponent:[key stringByAppendingPathExtension:extension]];
}

static NSCachedURLResponse *CPResponseFromMeta(NSDictionary *meta, NSData *body)
{
    CPHTTPURLResponse *response;
    NSURL *url = [NSURL URLWithString:[meta objectForKey:CPMetaURL]];

    if (url == nil || body == nil || [meta objectForKey:CPMetaHeaders] == nil)
        return nil;
    response = [[[CPHTTPURLResponse alloc]
                 initWithURL:url
                  statusCode:[[meta objectForKey:CPMetaStatus] intValue]
                headerFields:[meta objectForKey:CPMetaHeaders]
                    MIMEType:[meta objectForKey:CPMetaMIMEType]
               contentLength:[[meta objectForKey:CPMetaLength] longLongValue]
                textEncoding:[meta objectForKey:CPMetaEncoding]
           suggestedFilename:nil] autorelease];
    return [[[NSCachedURLResponse alloc] initWithResponse:response
                                                     data:body
                                                 userInfo:nil
                                            storagePolicy:NSURLCacheStorageNotAllowed] autorelease];
}

static void CPRememberInMemory(NSString *key, NSCachedURLResponse *entry)
{
    unsigned size;

    if (entry == nil || CPMemoryEntries == nil)
        return;
    size = (unsigned)[[entry data] length];
    if (size > CPMemoryCapacity)
        return;

    if ([CPMemoryEntries objectForKey:key] != nil)
        [CPMemoryOrder removeObject:key];
    else
        CPMemoryBytes += size;
    [CPMemoryEntries setObject:entry forKey:key];
    [CPMemoryOrder addObject:key];

    while (CPMemoryBytes > CPMemoryCapacity && [CPMemoryOrder count] > 0) {
        NSString *oldest = [CPMemoryOrder objectAtIndex:0];
        CPMemoryBytes -= (unsigned)[[[CPMemoryEntries objectForKey:oldest] data] length];
        [CPMemoryEntries removeObjectForKey:oldest];
        [CPMemoryOrder removeObjectAtIndex:0];
    }
}

// NSInteger is 10.5 and later.
static int CPCompareByDate(id left, id right, void *context)
{
    return [[left objectAtIndex:0] compare:[right objectAtIndex:0]];
}

// Drops the least recently written entries until the folder is comfortably
// under its limit. Runs after a store, by which time the page is already up.
static void CPEnforceDiskCapacity(void)
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator;
    NSMutableArray *bodies = [NSMutableArray array];
    NSArray *oldestFirst;
    NSString *name;
    unsigned long long total = 0;
    unsigned index;

    if (CPCacheRoot == nil)
        return;
    enumerator = [files enumeratorAtPath:CPCacheRoot];
    while ((name = [enumerator nextObject]) != nil) {
        NSDictionary *attributes = [enumerator fileAttributes];
        if (![[name pathExtension] isEqualToString:@"body"])
            continue;
        total += [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
        [bodies addObject:[NSArray arrayWithObjects:
                           [attributes objectForKey:NSFileModificationDate],
                           name,
                           [attributes objectForKey:NSFileSize], nil]];
    }
    if (total <= CPDiskCapacity)
        return;

    oldestFirst = [bodies sortedArrayUsingFunction:CPCompareByDate context:NULL];
    for (index = 0; index < [oldestFirst count] && total > (CPDiskCapacity * 0.85); index++) {
        NSArray *entry = [oldestFirst objectAtIndex:index];
        NSString *body = [CPCacheRoot stringByAppendingPathComponent:[entry objectAtIndex:1]];
        NSString *meta = [[body stringByDeletingPathExtension] stringByAppendingPathExtension:@"meta"];

        total -= [[entry objectAtIndex:2] unsignedLongLongValue];
        [files removeFileAtPath:body handler:nil];
        [files removeFileAtPath:meta handler:nil];
    }
    CPLog(@"cache trimmed to %.1f MB", (double)total / (1024.0 * 1024.0));
}

@implementation CPHTTPCache

+ (void)configureWithMemoryCapacity:(unsigned)memoryCapacity
                       diskCapacity:(unsigned)diskCapacity
                               path:(NSString *)path
{
    if (CPMemoryEntries == nil) {
        CPMemoryEntries = [[NSMutableDictionary alloc] init];
        CPMemoryOrder = [[NSMutableArray alloc] init];
    }
    CPMemoryCapacity = memoryCapacity;
    CPDiskCapacity = diskCapacity;
    [CPCacheRoot release];
    CPCacheRoot = [path copy];
    CPCreateDirectories(path);
}

+ (NSString *)cachePath
{
    return CPCacheRoot;
}

+ (void)emptyMemoryCache
{
    [CPMemoryEntries removeAllObjects];
    [CPMemoryOrder removeAllObjects];
    CPMemoryBytes = 0;
}

+ (void)removeAllCachedResponses
{
    [CPMemoryEntries removeAllObjects];
    [CPMemoryOrder removeAllObjects];
    CPMemoryBytes = 0;
    if (CPCacheRoot != nil) {
        [[NSFileManager defaultManager] removeFileAtPath:CPCacheRoot handler:nil];
        CPCreateDirectories(CPCacheRoot);
    }
}

+ (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request
{
    NSString *method = [request HTTPMethod];
    NSString *key = CPCacheKeyForRequest(request);
    NSCachedURLResponse *entry;
    NSDictionary *meta;
    NSDictionary *varyValues;
    NSEnumerator *varyNames;
    NSString *varyName;
    NSData *body;

    if (method != nil && ![method isEqualToString:@"GET"])
        return nil;
    // Spelled without "Local": the longer name arrived in 10.5.
    if ([request cachePolicy] == NSURLRequestReloadIgnoringCacheData)
        return nil;
    if (key == nil || CPCacheRoot == nil)
        return nil;

    // The in-memory layer is keyed by the URL itself, so it needs no such check.
    entry = [CPMemoryEntries objectForKey:[[request URL] absoluteString]];
    if (entry != nil)
        return entry;

    meta = [NSDictionary dictionaryWithContentsOfFile:CPEntryPath(key, @"meta")];
    if (meta == nil)
        return nil;
    if (![[meta objectForKey:CPMetaURL] isEqualToString:[[request URL] absoluteString]]) {
        CPLog(@"cache file belongs to a different URL, ignoring it");
        return nil;
    }
    // The stored copy only answers a request whose Vary headers still match.
    varyValues = [meta objectForKey:CPMetaVary];
    varyNames = [varyValues keyEnumerator];
    while ((varyName = [varyNames nextObject]) != nil) {
        NSString *current = [request valueForHTTPHeaderField:varyName];
        if (![[varyValues objectForKey:varyName] isEqualToString:(current != nil ? current : @"")]) {
            CPLog(@"lookup: Vary mismatch on %@", varyName);
            return nil;
        }
    }
    body = [NSData dataWithContentsOfFile:CPEntryPath(key, @"body")];
    entry = CPResponseFromMeta(meta, body);
    if (entry != nil)
        CPRememberInMemory([[request URL] absoluteString], entry);
    return entry;
}

+ (BOOL)cachedResponseIsFresh:(NSCachedURLResponse *)cached forRequest:(NSURLRequest *)request
{
    NSHTTPURLResponse *response;
    NSString *cacheControl;
    NSString *requestCacheControl;
    NSString *requestPragma;
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
    requestPragma = [request valueForHTTPHeaderField:@"Pragma"];
    // A nil Pragma header compares "equal" to anything, because messaging nil
    // returns 0 and NSOrderedSame is 0 -- which made every request look like a
    // demand for a fresh copy, and the cache never hit at all.
    if (CPCacheControlHas(requestCacheControl, @"no-cache") ||
        (requestPragma != nil && [requestPragma caseInsensitiveCompare:@"no-cache"] == NSOrderedSame))
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

    if (CPCacheRoot == nil)
        return NO;
    // Reading the cache leaves no trace; writing to it would.
    if ([[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled])
        return NO;
    if (method != nil && ![method isEqualToString:@"GET"])
        return NO;
    if ([response statusCode] != 200 && [response statusCode] != 301)
        return NO;
    if (CPCacheControlHas(CPHeader(response, @"Cache-Control"), @"no-store"))
        return NO;

    // "Vary: *" means the response cannot be matched to a later request at all.
    // Anything else is handled by remembering the request headers it varies on.
    // The nil check matters: -rangeOfString: sent to nil yields location 0,
    // which is not NSNotFound, so every response without a Vary header was
    // being refused.
    vary = CPHeader(response, @"Vary");
    if (vary != nil && [vary rangeOfString:@"*"].location != NSNotFound)
        return NO;

    return YES;
}

// The request header values a stored entry depends on, per its Vary header.
+ (NSDictionary *)varyValuesForResponse:(NSHTTPURLResponse *)response request:(NSURLRequest *)request
{
    NSString *vary = CPHeader(response, @"Vary");
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSArray *names;
    unsigned index;

    if ([vary length] == 0)
        return values;
    names = [vary componentsSeparatedByString:@","];
    for (index = 0; index < [names count]; index++) {
        NSString *name = [[names objectAtIndex:index]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *value;
        if ([name length] == 0)
            continue;
        value = [request valueForHTTPHeaderField:name];
        [values setObject:(value != nil ? value : @"") forKey:[name lowercaseString]];
    }
    return values;
}

+ (void)storeData:(NSData *)data
         response:(NSHTTPURLResponse *)response
       forRequest:(NSURLRequest *)request
{
    NSString *key = CPCacheKeyForRequest(request);
    NSMutableDictionary *meta;
    NSString *metaPath;
    NSString *bodyPath;

    if (data == nil || response == nil || key == nil || CPCacheRoot == nil)
        return;

    meta = [NSMutableDictionary dictionary];
    [meta setObject:[[request URL] absoluteString] forKey:CPMetaURL];
    [meta setObject:[NSNumber numberWithInt:[response statusCode]] forKey:CPMetaStatus];
    [meta setObject:[response allHeaderFields] forKey:CPMetaHeaders];
    [meta setObject:[NSNumber numberWithLongLong:(long long)[data length]] forKey:CPMetaLength];
    if ([response MIMEType] != nil)
        [meta setObject:[response MIMEType] forKey:CPMetaMIMEType];
    if ([response textEncodingName] != nil)
        [meta setObject:[response textEncodingName] forKey:CPMetaEncoding];
    [meta setObject:[CPHTTPCache varyValuesForResponse:response request:request] forKey:CPMetaVary];

    metaPath = CPEntryPath(key, @"meta");
    bodyPath = CPEntryPath(key, @"body");
    CPCreateDirectories([metaPath stringByDeletingLastPathComponent]);
    if (![data writeToFile:bodyPath atomically:NO]) {
        CPLog(@"store failed writing %@", bodyPath);
        return;
    }
    [meta writeToFile:metaPath atomically:NO];

    CPRememberInMemory([[request URL] absoluteString], CPResponseFromMeta(meta, data));
    CPEnforceDiskCapacity();
}

@end
