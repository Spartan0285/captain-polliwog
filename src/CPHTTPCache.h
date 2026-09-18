/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// HTTP caching rules for the bundled network stack. Foundation's own caching
// went unused once https stopped going through NSURLConnection, and on these
// machines a cache hit is worth more than elsewhere: it skips the download,
// the connection and the TLS handshake.
@interface CPHTTPCache : NSObject

// Storage of our own rather than NSURLCache: CFNetwork crashes reading back
// entries it did not write itself, and files avoid SQLite work on a G3.
+ (NSString *)cachePath;
+ (void)configureWithMemoryCapacity:(unsigned)memoryCapacity
                       diskCapacity:(unsigned)diskCapacity
                               path:(NSString *)path;
+ (void)removeAllCachedResponses;
// Drops only the in-memory layer; the files on disk stay.
+ (void)emptyMemoryCache;

// nil unless the request may be served or revalidated from the cache.
+ (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request;

// YES when the stored copy can be used with no network access at all.
+ (BOOL)cachedResponseIsFresh:(NSCachedURLResponse *)cached forRequest:(NSURLRequest *)request;

// If-None-Match / If-Modified-Since for a stale copy that carries validators.
+ (NSDictionary *)validatorHeadersForCachedResponse:(NSCachedURLResponse *)cached;

+ (BOOL)mayStoreResponse:(NSHTTPURLResponse *)response forRequest:(NSURLRequest *)request;
+ (NSDictionary *)varyValuesForResponse:(NSHTTPURLResponse *)response request:(NSURLRequest *)request;
+ (void)storeData:(NSData *)data
         response:(NSHTTPURLResponse *)response
       forRequest:(NSURLRequest *)request;

@end
