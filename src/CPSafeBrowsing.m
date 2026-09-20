/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPSafeBrowsing.h"

#include <openssl/evp.h>

static NSString * const CPSafeBrowsingEnabledKey = @"CPWarnsAboutDangerousSites";

// The file the list is read from: "CPSB1", the date it was made, how many
// prefixes follow, then that many 4-byte big-endian prefixes, sorted.
// scripts/make-safebrowsing-list.py writes it.
static const char CPSafeBrowsingMagic[5] = { 'C', 'P', 'S', 'B', '1' };

static NSData *prefixData = nil;        // the sorted prefixes, as they came
static const uint8_t *prefixBytes = NULL;
static unsigned prefixCount = 0;
static NSDate *listDate = nil;
static NSMutableSet *allowedSites = nil;

@implementation CPSafeBrowsing

+ (NSString *)listPath
{
    NSArray *folders = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                           NSUserDomainMask, YES);
    NSString *folder = [[folders objectAtIndex:0] stringByAppendingPathComponent:@"Captain Polliwog"];
    return [folder stringByAppendingPathComponent:@"safebrowsing.list"];
}

+ (void)start
{
    NSData *file = [NSData dataWithContentsOfFile:[self listPath]];
    const uint8_t *bytes = [file bytes];
    uint32_t stamp, count;

    if (allowedSites == nil)
        allowedSites = [[NSMutableSet alloc] init];
    if ([file length] < 13 || memcmp(bytes, CPSafeBrowsingMagic, 5) != 0)
        return;
    memcpy(&stamp, bytes + 5, 4);
    memcpy(&count, bytes + 9, 4);
    stamp = ntohl(stamp);
    count = ntohl(count);
    if ([file length] < 13 + (unsigned long long)count * 4)
        return;

    [prefixData release];
    prefixData = [file retain];
    prefixBytes = [prefixData bytes] + 13;
    prefixCount = count;
    [listDate release];
    listDate = [[NSDate dateWithTimeIntervalSince1970:stamp] retain];
    NSLog(@"Captain Polliwog: safe browsing list of %u prefixes, made %@", prefixCount, listDate);
}

+ (BOOL)isEnabled
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:CPSafeBrowsingEnabledKey] == nil
        || [defaults boolForKey:CPSafeBrowsingEnabledKey];
}

+ (void)setEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:CPSafeBrowsingEnabledKey];
}

+ (unsigned)entryCount { return prefixCount; }
+ (NSDate *)listDate { return listDate; }

#pragma mark Looking a URL up

// Safe Browsing hashes a canonical form of the URL. This is the part of that
// canonicalisation that matters here: lower-case host without a trailing dot
// or a "www." that the list would not carry, the path as given, and the
// query kept only for the variant that includes it.
static NSString *CPCanonicalHost(NSURL *url)
{
    NSString *host = [[url host] lowercaseString];

    while ([host hasSuffix:@"."])
        host = [host substringToIndex:[host length] - 1];
    return host;
}

// The list holds hashes of the forms the specification says to try: the host
// and up to four of its parents, each with the full path, then each shorter
// path, then the host alone. Thirty at the most.
+ (NSArray *)lookupStringsForURL:(NSURL *)url
{
    NSString *host = CPCanonicalHost(url);
    NSString *path = [url path];
    NSString *query = [url query];
    NSMutableArray *hosts = [NSMutableArray array];
    NSMutableArray *paths = [NSMutableArray array];
    NSMutableArray *combinations = [NSMutableArray array];
    NSArray *labels;
    unsigned index, hostIndex, pathIndex;

    if ([host length] == 0)
        return combinations;
    if ([path length] == 0)
        path = @"/";

    [hosts addObject:host];
    labels = [host componentsSeparatedByString:@"."];
    // example.com from www.example.com, and so on, five hosts at the most.
    for (index = 1; index + 1 < [labels count] && [hosts count] < 5; index++) {
        NSArray *tail = [labels subarrayWithRange:NSMakeRange(index, [labels count] - index)];
        if ([tail count] < 2)
            break;
        [hosts addObject:[tail componentsJoinedByString:@"."]];
    }

    if (query != nil)
        [paths addObject:[NSString stringWithFormat:@"%@?%@", path, query]];
    [paths addObject:path];
    {
        // /a/b/c.html gives /a/b/, /a/ and /; four paths at the most.
        NSString *directory = path;
        while ([paths count] < 4) {
            NSRange slash = [directory rangeOfString:@"/" options:NSBackwardsSearch
                                               range:NSMakeRange(0, [directory length] > 0 ? [directory length] - 1 : 0)];
            if (slash.location == NSNotFound)
                break;
            directory = [directory substringToIndex:slash.location + 1];
            if ([paths containsObject:directory])
                break;
            [paths addObject:directory];
            if ([directory isEqualToString:@"/"])
                break;
        }
    }

    for (hostIndex = 0; hostIndex < [hosts count]; hostIndex++) {
        for (pathIndex = 0; pathIndex < [paths count]; pathIndex++) {
            [combinations addObject:[NSString stringWithFormat:@"%@%@",
                [hosts objectAtIndex:hostIndex], [paths objectAtIndex:pathIndex]]];
        }
    }
    return combinations;
}

static uint32_t CPPrefixOfString(NSString *string)
{
    NSData *bytes = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int length = 0;
    EVP_MD_CTX *context = EVP_MD_CTX_new();
    uint32_t prefix = 0;

    if (context == NULL)
        return 0;
    if (EVP_DigestInit_ex(context, EVP_sha256(), NULL)) {
        EVP_DigestUpdate(context, [bytes bytes], [bytes length]);
        EVP_DigestFinal_ex(context, digest, &length);
    }
    EVP_MD_CTX_free(context);
    if (length < 4)
        return 0;
    prefix = ((uint32_t)digest[0] << 24) | ((uint32_t)digest[1] << 16)
           | ((uint32_t)digest[2] << 8) | (uint32_t)digest[3];
    return prefix;
}

// The prefixes are sorted, so this is a binary search over the file as it
// sits in memory - no parsing, no allocation, a handful of comparisons.
static BOOL CPListContainsPrefix(uint32_t prefix)
{
    unsigned low = 0, high = prefixCount;

    if (prefixBytes == NULL || prefixCount == 0)
        return NO;
    while (low < high) {
        unsigned middle = low + (high - low) / 2;
        const uint8_t *entry = prefixBytes + middle * 4;
        uint32_t value = ((uint32_t)entry[0] << 24) | ((uint32_t)entry[1] << 16)
                       | ((uint32_t)entry[2] << 8) | (uint32_t)entry[3];
        if (value == prefix)
            return YES;
        if (value < prefix)
            low = middle + 1;
        else
            high = middle;
    }
    return NO;
}

+ (BOOL)isDangerous:(NSURL *)url
{
    NSString *scheme = [[url scheme] lowercaseString];
    NSArray *combinations;
    unsigned index;

    if (prefixCount == 0 || ![self isEnabled])
        return NO;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        return NO;
    if ([allowedSites containsObject:CPCanonicalHost(url)])
        return NO;

    combinations = [self lookupStringsForURL:url];
    for (index = 0; index < [combinations count]; index++) {
        if (CPListContainsPrefix(CPPrefixOfString([combinations objectAtIndex:index])))
            return YES;
    }
    return NO;
}

+ (void)allowOnce:(NSURL *)url
{
    NSString *host = CPCanonicalHost(url);

    if (allowedSites == nil)
        allowedSites = [[NSMutableSet alloc] init];
    if (host != nil)
        [allowedSites addObject:host];
}

#pragma mark The warning

+ (NSString *)warningPageHTMLForURL:(NSURL *)url
{
    NSString *host = CPCanonicalHost(url);
    NSString *address = [url absoluteString];

    return [NSString stringWithFormat:
        @"<!DOCTYPE html><meta charset=\"utf-8\"><title>Warning</title>"
        @"<style>"
        @"body { margin: 0; font: 14px/1.5 'Lucida Grande', sans-serif; background: #8b1a1a; color: #fff; }"
        @".sheet { max-width: 34em; margin: 12vh auto; padding: 0 24px; }"
        @"h1 { font-size: 22px; margin: 0 0 12px 0; }"
        @"p { margin: 0 0 14px 0; }"
        @".site { font-weight: bold; word-break: break-all; }"
        @".buttons { margin-top: 22px; }"
        @"button { font: inherit; padding: 6px 14px; margin-right: 10px; }"
        @".small { font-size: 12px; opacity: 0.85; }"
        @"</style>"
        @"<div class=\"sheet\">"
        @"<h1>This site may be dangerous</h1>"
        @"<p><span class=\"site\">%@</span> matches Captain Polliwog's list of sites "
        @"reported for phishing or for distributing malware.</p>"
        @"<p>Sites like these try to trick you into giving away passwords or card "
        @"numbers, or into installing software you did not ask for.</p>"
        @"<div class=\"buttons\">"
        @"<button onclick=\"history.back()\">Go Back</button>"
        @"<button onclick=\"location.href='x-polliwog-proceed:%@'\">Visit Anyway</button>"
        @"</div>"
        @"<p class=\"small\">The check happens on this Mac: the address was compared "
        @"against a list kept here, and was not sent anywhere. A four-byte match is "
        @"not proof, so a site can land here by coincidence.</p>"
        @"</div>",
        host != nil ? host : @"This address", address];
}

@end
