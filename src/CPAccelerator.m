/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAccelerator.h"
#include <Security/Security.h>
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>
#include <curl/curl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>

NSString * const CPAcceleratorStatusDidChangeNotification = @"CPAcceleratorStatusDidChange";

static NSString * const CPAcceleratorEnabledKey = @"CPAcceleratorEnabled";
static NSString * const CPAcceleratorVMBase = @"http://10.0.2.100:7780/";
static NSString * const CPAcceleratorServiceType = @"_poweremu-web._tcp.";
// A generic Keychain item of Captain Polliwog's own (not a web login, which
// AutoFill would list).
static const char CPAcceleratorKeychainService[] = "Captain Polliwog: PowerEmu pairing code";
static const char CPAcceleratorKeychainAccount[] = "PowerEmu";
static const NSTimeInterval CPAcceleratorFailurePause = 60.0;
static const NSTimeInterval CPAcceleratorRetryInterval = 300.0;

// State shared with the network thread, under the lock.
static NSLock *stateLock = nil;
static NSString *baseURL = nil;             // nil: not available
static NSString *serverName = nil;          // "Adam's MacBook Air"
static NSString *token = nil;               // for a PowerEmu on the network
static NSTimeInterval failedUntil = 0;
static BOOL probing = NO;
static BOOL sawServiceWithoutCode = NO;
static BOOL pairingRejected = NO;

static NSNetServiceBrowser *browser = nil;
static NSMutableArray *services = nil;
static NSTimer *retryTimer = nil;

@interface CPAccelerator (Private)
+ (void)probe;
+ (void)probeThread:(id)unused;
+ (NSDictionary *)helloAt:(NSString *)base token:(NSString *)code connectTimeoutMs:(long)timeout status:(long *)status;
+ (void)browseNetwork;
+ (void)stopBrowsing;
+ (void)finishedProbeWithBase:(NSString *)base name:(NSString *)name token:(NSString *)code;
+ (void)postStatus;
@end

static size_t CPAcceleratorCollect(char *bytes, size_t size, size_t count, void *context)
{
    [(NSMutableData *)context appendBytes:bytes length:size * count];
    return size * count;
}

// Private networks, loopback and .local names are reached directly.
static BOOL CPIsLocalHost(NSString *host)
{
    struct in_addr address;
    uint32_t value;

    if (host == nil || [host length] == 0)
        return YES;
    host = [host lowercaseString];
    if ([host isEqualToString:@"localhost"] || [host hasSuffix:@".local"] || [host hasSuffix:@".local."])
        return YES;
    if ([host rangeOfString:@":"].location != NSNotFound)
        return YES;     // an IPv6 literal: leave it alone
    if (inet_aton([host UTF8String], &address) == 0)
        return NO;
    value = ntohl(address.s_addr);
    return (value >> 24) == 127 || (value >> 24) == 10 || (value >> 16) == 0xC0A8 ||
           (value >> 20) == 0xAC1 || (value >> 16) == 0xA9FE;
}

@implementation CPAccelerator

+ (void)initialize
{
    if (self == [CPAccelerator class])
        stateLock = [[NSLock alloc] init];
}

+ (BOOL)isEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:CPAcceleratorEnabledKey];
    return value == nil || [value boolValue];
}

+ (void)setEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:CPAcceleratorEnabledKey];
    [self start];
}

+ (NSString *)pairingCode
{
    UInt32 length = 0;
    void *data = NULL;
    NSString *code = nil;

    if (SecKeychainFindGenericPassword(NULL, strlen(CPAcceleratorKeychainService), CPAcceleratorKeychainService,
                                       strlen(CPAcceleratorKeychainAccount), CPAcceleratorKeychainAccount,
                                       &length, &data, NULL) == noErr) {
        code = [[[NSString alloc] initWithBytes:data length:length encoding:NSUTF8StringEncoding] autorelease];
        SecKeychainItemFreeContent(NULL, data);
    }
    return code;
}

+ (void)setPairingCode:(NSString *)code
{
    code = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    {
        SecKeychainItemRef item = NULL;
        const char *secret = [code UTF8String];
        if (SecKeychainFindGenericPassword(NULL, strlen(CPAcceleratorKeychainService), CPAcceleratorKeychainService,
                                           strlen(CPAcceleratorKeychainAccount), CPAcceleratorKeychainAccount,
                                           NULL, NULL, &item) != noErr)
            item = NULL;
        if ([code length] == 0) {
            if (item != NULL)
                SecKeychainItemDelete(item);
        } else if (item != NULL) {
            SecKeychainItemModifyAttributesAndData(item, NULL, strlen(secret), secret);
        } else {
            SecKeychainAddGenericPassword(NULL, strlen(CPAcceleratorKeychainService), CPAcceleratorKeychainService,
                                          strlen(CPAcceleratorKeychainAccount), CPAcceleratorKeychainAccount,
                                          strlen(secret), secret, NULL);
        }
        if (item != NULL)
            CFRelease(item);
    }
    [stateLock lock];
    pairingRejected = NO;
    [stateLock unlock];
    [self start];
}

+ (void)start
{
    [self engineHeader];    // computed here, on the main thread (it asks NSScreen)
    [stateLock lock];
    [baseURL release];
    baseURL = nil;
    failedUntil = 0;
    [stateLock unlock];
    [self stopBrowsing];
    if ([self isEnabled])
        [self probe];
    [self postStatus];
    if (retryTimer == nil) {
        retryTimer = [[NSTimer scheduledTimerWithTimeInterval:CPAcceleratorRetryInterval target:self
                                                     selector:@selector(retryTimerFired:) userInfo:nil repeats:YES] retain];
    }
}

+ (void)retryTimerFired:(NSTimer *)timer
{
    BOOL available;
    [stateLock lock];
    available = baseURL != nil;
    [stateLock unlock];
    if (!available && [self isEnabled])
        [self probe];
}

+ (BOOL)shouldRoute:(NSURL *)url
{
    NSString *scheme = [[url scheme] lowercaseString];
    BOOL route;
    BOOL reprobe = NO;

    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]))
        return NO;
    if (CPIsLocalHost([url host]))
        return NO;
    [stateLock lock];
    route = baseURL != nil;
    if (route && failedUntil > 0) {
        if ([NSDate timeIntervalSinceReferenceDate] < failedUntil)
            route = NO;
        else {
            // The pause is over: check PowerEmu is back before using it.
            failedUntil = 0;
            route = NO;
            reprobe = YES;
        }
    }
    [stateLock unlock];
    if (reprobe)
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
    return route;
}

+ (NSString *)baseURL
{
    NSString *result;
    [stateLock lock];
    result = [[baseURL retain] autorelease];
    [stateLock unlock];
    return result;
}

+ (NSString *)token
{
    NSString *result;
    [stateLock lock];
    result = [[token retain] autorelease];
    [stateLock unlock];
    return result;
}

+ (NSString *)engineHeader
{
    static NSString *header = nil;
    if (header == nil) {
        // "5604.5.6" (a Leopard build of 604) or "4533.19.4" (Tiger's): the
        // leading digit is the OS's.
        NSString *version = [[NSBundle bundleForClass:[WebView class]] objectForInfoDictionaryKey:@"CFBundleVersion"];
        NSArray *parts = [version componentsSeparatedByString:@"."];
        NSString *major = [parts count] > 0 ? [parts objectAtIndex:0] : @"533";
        NSString *minor = [parts count] > 1 ? [parts objectAtIndex:1] : @"0";
        NSRect screen = [[NSScreen mainScreen] frame];
        int edge = (int)MAX(NSWidth(screen), NSHeight(screen));
        if ([major length] == 4)
            major = [major substringFromIndex:1];
        // The 2018 engine with Captain Polliwog's backports parses ES2020
        // (optional chaining, nullish coalescing) and more; the system
        // engines ES5.
        header = [[NSString alloc] initWithFormat:@"webkit=%@.%@; js=%@; images=jpeg,png,gif; max-image=%d",
                  major, minor, [major intValue] >= 604 ? @"es2020" : @"es5", edge];
    }
    return header;
}

+ (void)markFailed
{
    [stateLock lock];
    failedUntil = [NSDate timeIntervalSinceReferenceDate] + CPAcceleratorFailurePause;
    [stateLock unlock];
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: PowerEmu unreachable; going direct for %.0fs", CPAcceleratorFailurePause);
    [self performSelectorOnMainThread:@selector(postStatus) withObject:nil waitUntilDone:NO];
}

+ (void)markPairingRejected
{
    [stateLock lock];
    pairingRejected = YES;
    [baseURL release];
    baseURL = nil;
    [stateLock unlock];
    [self performSelectorOnMainThread:@selector(postStatus) withObject:nil waitUntilDone:NO];
}

+ (BOOL)needsPairingCode
{
    BOOL needs;
    [stateLock lock];
    needs = baseURL == nil && (pairingRejected || sawServiceWithoutCode);
    [stateLock unlock];
    return needs;
}

+ (NSString *)statusDescription
{
    NSString *status;

    if (![self isEnabled])
        return @"Off.";
    [stateLock lock];
    if (baseURL != nil && failedUntil > 0)
        status = @"PowerEmu stopped answering; browsing directly for now.";
    else if (baseURL != nil)
        status = [NSString stringWithFormat:@"Using PowerEmu on %@.", serverName != nil ? serverName : @"this Mac"];
    else if (pairingRejected)
        status = @"PowerEmu didn't accept the pairing code. Enter the one its Service Hub shows.";
    else if (sawServiceWithoutCode)
        status = @"Found PowerEmu on the network. Enter the pairing code its Service Hub shows to use it.";
    else if (probing)
        status = @"Looking for PowerEmu...";
    else
        status = @"PowerEmu not found.";
    [stateLock unlock];
    return status;
}

@end

@implementation CPAccelerator (Private)

+ (void)postStatus
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CPAcceleratorStatusDidChangeNotification object:nil];
}

+ (void)probe
{
    [stateLock lock];
    if (probing) {
        [stateLock unlock];
        return;
    }
    probing = YES;
    sawServiceWithoutCode = NO;
    [stateLock unlock];
    [NSThread detachNewThreadSelector:@selector(probeThread:) toTarget:self withObject:nil];
}

// Background thread: are we inside a PowerEmu virtual Mac?
+ (void)probeThread:(id)unused
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    long status = 0;
    NSDictionary *hello = [self helloAt:CPAcceleratorVMBase token:nil connectTimeoutMs:300 status:&status];

    if (hello != nil) {
        [self finishedProbeWithBase:CPAcceleratorVMBase name:[hello objectForKey:@"name"] token:nil];
    } else {
        // Not a virtual Mac: look on the network, from the main run loop.
        [self performSelectorOnMainThread:@selector(browseNetwork) withObject:nil waitUntilDone:NO];
    }
    [pool release];
}

// The hello exchange: the answer's "key: value" lines, or nil when there is
// no accelerator there (or it wants a pairing code: *status is then 401).
+ (NSDictionary *)helloAt:(NSString *)base token:(NSString *)code connectTimeoutMs:(long)timeout status:(long *)status
{
    CURL *easy = curl_easy_init();
    struct curl_slist *headers = NULL;
    NSMutableData *body = [NSMutableData data];
    NSMutableDictionary *answer = nil;
    CURLcode result;

    *status = 0;
    if (easy == NULL)
        return nil;
    curl_easy_setopt(easy, CURLOPT_URL, [[base stringByAppendingString:@".poweremu/v1/hello"] UTF8String]);
    curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT_MS, timeout);
    curl_easy_setopt(easy, CURLOPT_TIMEOUT_MS, 3000L);
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, CPAcceleratorCollect);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, body);
    if (code != nil)
        headers = curl_slist_append(headers, [[@"X-PowerEmu-Token: " stringByAppendingString:code] UTF8String]);
    curl_easy_setopt(easy, CURLOPT_HTTPHEADER, headers);
    result = curl_easy_perform(easy);
    if (result == CURLE_OK)
        curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, status);
    curl_easy_cleanup(easy);
    curl_slist_free_all(headers);

    if (result == CURLE_OK && *status == 200) {
        NSString *text = [[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] autorelease];
        NSEnumerator *lines = [[text componentsSeparatedByString:@"\n"] objectEnumerator];
        NSString *line;
        answer = [NSMutableDictionary dictionary];
        while ((line = [lines nextObject]) != nil) {
            NSRange colon = [line rangeOfString:@":"];
            if (colon.location == NSNotFound)
                continue;
            [answer setObject:[[line substringFromIndex:NSMaxRange(colon)]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                       forKey:[[line substringToIndex:colon.location] lowercaseString]];
        }
        if (![[answer objectForKey:@"service"] isEqualToString:@"PowerEmu Web Accelerator"])
            answer = nil;
    }
    return answer;
}

+ (void)browseNetwork
{
    [self stopBrowsing];
    services = [[NSMutableArray alloc] init];
    browser = [[NSNetServiceBrowser alloc] init];
    [browser setDelegate:(id)self];
    [browser searchForServicesOfType:CPAcceleratorServiceType inDomain:@"local."];
    // Two seconds to find one, as the protocol suggests.
    [self performSelector:@selector(browseTimedOut) withObject:nil afterDelay:2.0];
}

+ (void)browseTimedOut
{
    BOOL found;
    [stateLock lock];
    found = baseURL != nil;
    [stateLock unlock];
    if (!found && [services count] == 0) {
        [self stopBrowsing];
        [self finishedProbeWithBase:nil name:nil token:nil];
    }
}

+ (void)stopBrowsing
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(browseTimedOut) object:nil];
    [browser setDelegate:nil];
    [browser stop];
    [browser release];
    browser = nil;
    [services makeObjectsPerformSelector:@selector(stop)];
    [services release];
    services = nil;
}

+ (void)netServiceBrowser:(NSNetServiceBrowser *)aBrowser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing
{
    NSString *code = [self pairingCode];
    if ([code length] == 0) {
        // Found, but using it over the network is the user's choice.
        [stateLock lock];
        sawServiceWithoutCode = YES;
        [stateLock unlock];
        [self stopBrowsing];
        [self finishedProbeWithBase:nil name:[service name] token:nil];
        return;
    }
    [services addObject:service];
    [service setDelegate:(id)self];
    [service resolveWithTimeout:3.0];
}

+ (void)netServiceDidResolveAddress:(NSNetService *)service
{
    NSEnumerator *addresses = [[service addresses] objectEnumerator];
    NSData *data;

    // An IPv4 address: the home network may have no IPv6 route, and Tiger
    // tries IPv6 first.
    while ((data = [addresses nextObject]) != nil) {
        const struct sockaddr *address = (const struct sockaddr *)[data bytes];
        if ([data length] >= sizeof(struct sockaddr_in) && address->sa_family == AF_INET) {
            const struct sockaddr_in *ipv4 = (const struct sockaddr_in *)address;
            NSString *base = [NSString stringWithFormat:@"http://%s:%u/", inet_ntoa(ipv4->sin_addr), ntohs(ipv4->sin_port)];
            NSArray *candidate = [NSArray arrayWithObjects:base, [service name], [self pairingCode], nil];
            [self stopBrowsing];
            [NSThread detachNewThreadSelector:@selector(helloThread:) toTarget:self withObject:candidate];
            return;
        }
    }
}

+ (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errors
{
    [self stopBrowsing];
    [self finishedProbeWithBase:nil name:nil token:nil];
}

// Background thread: say hello to a PowerEmu found on the network.
+ (void)helloThread:(NSArray *)candidate
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *base = [candidate objectAtIndex:0];
    NSString *code = [candidate count] > 2 ? [candidate objectAtIndex:2] : nil;
    long status = 0;
    NSDictionary *hello = [self helloAt:base token:code connectTimeoutMs:1500 status:&status];

    if (hello != nil) {
        [self finishedProbeWithBase:base name:[hello objectForKey:@"name"] token:code];
    } else {
        if (status == 401) {
            [stateLock lock];
            pairingRejected = YES;
            [stateLock unlock];
        }
        [self finishedProbeWithBase:nil name:[candidate objectAtIndex:1] token:nil];
    }
    [pool release];
}

+ (void)finishedProbeWithBase:(NSString *)base name:(NSString *)name token:(NSString *)code
{
    [stateLock lock];
    [baseURL release];
    baseURL = [base copy];
    [serverName release];
    serverName = [name copy];
    [token release];
    token = [code copy];
    failedUntil = 0;
    probing = NO;
    if (base != nil)
        pairingRejected = NO;
    [stateLock unlock];
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: PowerEmu accelerator %@", base != nil ? base : @"not available");
    [self performSelectorOnMainThread:@selector(postStatus) withObject:nil waitUntilDone:NO];
}

@end
