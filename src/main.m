/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Captain Polliwog - a web browser for Mac OS X 10.4 Tiger and later.

#import <Cocoa/Cocoa.h>
#import "CPAppDelegate.h"
#include <mach-o/dyld.h>
#include <sys/param.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Is this system at least `minimum` ("10.4", "10.5")? Gestalt, because this
// runs before anything else is loaded and needs nothing but CoreServices.
static BOOL CPSystemIsAtLeast(NSString *minimum)
{
    SInt32 major = 10, minor = 0;
    NSArray *parts = [minimum componentsSeparatedByString:@"."];
    int wantMajor = [parts count] > 0 ? [[parts objectAtIndex:0] intValue] : 10;
    int wantMinor = [parts count] > 1 ? [[parts objectAtIndex:1] intValue] : 0;

    Gestalt(gestaltSystemVersionMajor, &major);
    Gestalt(gestaltSystemVersionMinor, &minor);
    return major > wantMajor || (major == wantMajor && minor >= wantMinor);
}

// The browser's own WebKit lives in Contents/Frameworks, and dyld only looks
// there if DYLD_FRAMEWORK_PATH says so. The Info.plist asks LaunchServices to
// set it (LSEnvironment), and that is not dependable: on a Tiger PowerBook,
// installed in /Applications, the running process had no DYLD_FRAMEWORK_PATH
// at all and had quietly loaded Tiger's own WebKit from 2009 - which is why
// modern pages struggled there. LSEnvironment also only ever named one fixed
// path, so the engine was lost the moment the app lived anywhere else.
//
// So the app points dyld at its engine itself, here, before a single Cocoa
// class is touched: it sets the path and executes itself again in place. Same
// process, same arguments - the -psn_ LaunchServices passed goes through with
// them - and this time the engine loads from wherever the app is.
//
// Only when the engine is one this system can run. Pointing Tiger at a
// Leopard engine would stop the browser launching at all, which is worse
// than the system WebKit it would otherwise fall back to; each engine says
// what it needs in its own Info.plist (package-webkit.sh writes it), and an
// engine that says nothing is assumed to need Leopard, which is what every
// build before this one was.
static void CPUseBundledEngine(int argc, const char *argv[])
{
    char executable[MAXPATHLEN], resolved[MAXPATHLEN];
    uint32_t size = sizeof executable;
    NSAutoreleasePool *pool;
    NSString *contents, *frameworks, *minimum, *current;
    NSDictionary *engineInfo;

    if (getenv("CP_ENGINE_CHOSEN") != NULL)
        return;     // this is the second time through
    if (_NSGetExecutablePath(executable, &size) != 0 || realpath(executable, resolved) == NULL)
        return;

    pool = [[NSAutoreleasePool alloc] init];
    // .../Captain Polliwog.app/Contents/MacOS/CaptainPolliwog -> .../Contents
    contents = [[[NSString stringWithUTF8String:resolved]
                    stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    frameworks = [contents stringByAppendingPathComponent:@"Frameworks"];
    engineInfo = [NSDictionary dictionaryWithContentsOfFile:
        [frameworks stringByAppendingPathComponent:@"WebKit.framework/Resources/Info.plist"]];
    minimum = [engineInfo objectForKey:@"LSMinimumSystemVersion"];
    if (minimum == nil)
        minimum = @"10.5";
    current = getenv("DYLD_FRAMEWORK_PATH") != NULL
        ? [NSString stringWithUTF8String:getenv("DYLD_FRAMEWORK_PATH")] : nil;

    if (engineInfo != nil && CPSystemIsAtLeast(minimum)
        && (current == nil || [current rangeOfString:frameworks].location == NSNotFound)) {
        setenv("DYLD_FRAMEWORK_PATH", [frameworks fileSystemRepresentation], 1);
        setenv("CP_ENGINE_CHOSEN", "1", 1);
        execv(resolved, (char * const *)argv);
        // Only reached if exec failed; carry on with whatever loaded.
    }
    [pool release];
}

int main(int argc, const char *argv[])
{
    CPUseBundledEngine(argc, argv);

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];

    // No nib: the menu bar is built in code so the same sources work with
    // Xcode 2.5 (Tiger) and Xcode 3.1 (Leopard) without Interface Builder files.
    CPAppDelegate *delegate = [[CPAppDelegate alloc] init];
    [app setDelegate:delegate];
    [delegate buildMainMenu];

    [app run];

    [delegate release];
    [pool release];
    return 0;
}
