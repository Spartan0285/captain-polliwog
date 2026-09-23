/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Methods Leopard added to classes Tiger already had.
//
// These do not show up as missing symbols - a method is a string in a
// table, not a link-time name - so they are found by running the thing and
// reading "selector not recognized". WebKit asks +[NSThread isMainThread]
// constantly, and an exception on that path stops a page loading without
// stopping the browser, which is the kind of failure that looks like a
// mystery.
//
// Each is added only if the class does not already answer it, so this same
// library is harmless on a system that has them.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <objc/objc-runtime.h>
#include <pthread.h>

#pragma mark NSThread

static NSThread *CPMainThread;
static NSRunLoop *CPMainRunLoop;
static pthread_t CPMainPThread;

@interface NSObject (CPTigerMainThread)
@end

@implementation NSObject (CPTigerMainThread)

// +load runs while the application is still single-threaded, which makes
// this thread the main one by definition.
+ (void)load
{
    if (CPMainThread == nil) {
        CPMainThread = [[NSThread currentThread] retain];
        CPMainRunLoop = [[NSRunLoop currentRunLoop] retain];
        CPMainPThread = pthread_self();
    }
}

@end

@implementation NSThread (CPTigerAdditions)

+ (NSThread *)mainThread
{
    return CPMainThread;
}

+ (BOOL)isMainThread
{
    return pthread_main_np() != 0 || pthread_equal(pthread_self(), CPMainPThread) != 0;
}

- (BOOL)isMainThread
{
    return self == CPMainThread;
}

@end

// +[NSRunLoop mainRunLoop] is Leopard's. This is the run loop of the thread
// that loaded us, which is the main one.
@implementation NSRunLoop (CPTigerAdditions)

+ (NSRunLoop *)mainRunLoop
{
    return CPMainRunLoop;
}

@end

#pragma mark NSFileManager

// The 10.5 file manager: the same work as Tiger's calls, with an error to
// fill in rather than a Boolean to interpret.
@implementation NSFileManager (CPTigerAdditions)

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path error:(NSError **)error
{
    NSDictionary *attributes = [self fileSystemAttributesAtPath:path];
    if (attributes == nil && error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:nil];
    return attributes;
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error
{
    NSDictionary *attributes = [self fileAttributesAtPath:path traverseLink:NO];
    if (attributes == nil && error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:nil];
    return attributes;
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error
{
    NSArray *contents = [self directoryContentsAtPath:path];
    if (contents == nil && error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:260 userInfo:nil];
    return contents;
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)intermediates
                   attributes:(NSDictionary *)attributes error:(NSError **)error
{
    BOOL made = intermediates
        ? [self createDirectoryAtPath:path attributes:attributes]
        : [self createDirectoryAtPath:path attributes:attributes];
    if (!made && intermediates) {
        // Tiger makes one directory at a time.
        NSMutableString *sofar = [NSMutableString string];
        NSEnumerator *parts = [[path pathComponents] objectEnumerator];
        NSString *part;
        while ((part = [parts nextObject]) != nil) {
            [sofar appendString:part];
            if (![sofar hasSuffix:@"/"])
                [sofar appendString:@"/"];
            if (![self fileExistsAtPath:sofar])
                [self createDirectoryAtPath:sofar attributes:attributes];
        }
        made = [self fileExistsAtPath:path];
    }
    if (!made && error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:512 userInfo:nil];
    return made;
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error
{
    BOOL removed = [self removeFileAtPath:path handler:nil];
    if (!removed && error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:4 userInfo:nil];
    return removed;
}

- (BOOL)moveItemAtPath:(NSString *)from toPath:(NSString *)to error:(NSError **)error
{
    BOOL moved = [self movePath:from toPath:to handler:nil];
    if (!moved && error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:4 userInfo:nil];
    return moved;
}

- (BOOL)copyItemAtPath:(NSString *)from toPath:(NSString *)to error:(NSError **)error
{
    BOOL copied = [self copyPath:from toPath:to handler:nil];
    if (!copied && error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:4 userInfo:nil];
    return copied;
}

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error
{
    return [self pathContentOfSymbolicLinkAtPath:path];
}

@end

#pragma mark Strings

@implementation NSString (CPTigerAdditions)

- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement
{
    return [[self componentsSeparatedByString:target] componentsJoinedByString:replacement];
}

- (NSArray *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)separators
{
    NSMutableArray *parts = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:self];
    [scanner setCharactersToBeSkipped:nil];
    while (![scanner isAtEnd]) {
        NSString *part = nil;
        if ([scanner scanUpToCharactersFromSet:separators intoString:&part])
            [parts addObject:part];
        else
            [parts addObject:@""];
        [scanner scanCharactersFromSet:separators intoString:NULL];
    }
    return parts;
}

@end

#pragma mark AppKit

// Colour spaces Leopard named. Tiger's generic RGB is the same space sRGB
// describes for everything the engine does with it: drawing and comparing.
@implementation NSColorSpace (CPTigerAdditions)

+ (NSColorSpace *)sRGBColorSpace
{
    return [NSColorSpace genericRGBColorSpace];
}

+ (NSColorSpace *)adobeRGB1998ColorSpace
{
    return [NSColorSpace genericRGBColorSpace];
}

+ (NSColorSpace *)genericGamma22GrayColorSpace
{
    return [NSColorSpace genericGrayColorSpace];
}

@end

// The class-side event state, which Leopard added for code that asks
// "what is held down now?" rather than reading it from an event.
@implementation NSEvent (CPTigerAdditions)

+ (NSUInteger)modifierFlags
{
    NSEvent *current = [NSApp currentEvent];
    return current != nil ? [current modifierFlags] : 0;
}

@end

// Colour conversion by colour space object, rather than by name (10.5).
@implementation NSColor (CPTigerAdditions)

- (NSColor *)colorUsingColorSpace:(NSColorSpace *)space
{
    return [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
}

@end

// Window collection behaviour (Spaces) arrived with Leopard; Tiger has no
// Spaces, so there is nothing to tell it.
@implementation NSWindow (CPTigerAdditions)

- (NSUInteger)collectionBehavior { return 0; }
- (void)setCollectionBehavior:(NSUInteger)behavior { }

@end

// Leopard let a request say which text encodings to try when a download's
// Content-Disposition filename is not labelled. Tiger decodes it as UTF-8
// and falls back to Latin-1, which is what an empty list here means.
@implementation NSMutableURLRequest (CPTigerAdditions)

- (void)setContentDispositionEncodingFallbackArray:(NSArray *)encodings { }

@end

@implementation NSURLRequest (CPTigerAdditions)

- (NSArray *)contentDispositionEncodingFallbackArray { return nil; }

@end

#pragma mark NSURLConnection

// WebKit starts every load through a private initializer Leopard's
// Foundation has and Tiger's has not. Without it nothing loads at all: the
// exception is swallowed, the connection is never made, and the page sits
// there until the stall report gives up.
//
// Tiger's connections start as soon as they are made and schedule
// themselves on the current run loop, so the later-start and scheduling
// calls have nothing to do here.
@implementation NSURLConnection (CPTigerAdditions)

- (id)_initWithRequest:(NSURLRequest *)request delegate:(id)delegate usesCache:(BOOL)usesCache
      maxContentLength:(long long)maxContentLength startImmediately:(BOOL)startImmediately
{
    return [self initWithRequest:request delegate:delegate];
}

- (id)_initWithRequest:(NSURLRequest *)request delegate:(id)delegate usesCache:(BOOL)usesCache
      maxContentLength:(long long)maxContentLength startImmediately:(BOOL)startImmediately
           connectionProperties:(NSDictionary *)properties
{
    return [self initWithRequest:request delegate:delegate];
}

- (void)start { }
- (void)scheduleInRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode { }
- (void)unscheduleFromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode { }
- (void)setDelegateQueue:(id)queue { }

@end

// WebCore reaches through a request to the CFNetwork object behind it, to
// set a priority, ask for pipelining, or attach a body. Tiger's Foundation
// has no such accessor, and an unrecognized selector here is not a small
// thing: Tiger's Objective-C runtime raises with longjmp, which walks the
// stack without running a single C++ destructor on the way. Anything JSC
// was holding - which thread is executing, which call frame is current - is
// left as it was, and the next piece of code to ask crashes reading it.
// That is how a missing accessor turns into a crash in the inspector's
// stack walker, two callbacks later.
//
// Answering null puts every one of those calls into a stub that ignores it
// (engine/tiger-shim/CoreFoundationStubs.c); the request still goes out,
// through Foundation, without the tuning.
@implementation NSURLRequest (CPTigerCFAccess)

- (void *)_CFURLRequest { return NULL; }

@end

// WebCore reads a response's headers from the CFNetwork message behind it.
// Tiger's Foundation has no such accessor, and this browser's responses are
// its own anyway; answering null sends WebCore down the -allHeaderFields
// path it already falls back to (engine patch: "Read an NSURLProtocol
// response's headers from -allHeaderFields").
@implementation NSURLResponse (CPTigerAdditions)

- (void *)_CFURLResponse { return NULL; }

@end
