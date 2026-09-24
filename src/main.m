/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// Captain Polliwog - a web browser for Mac OS X 10.4 Tiger and later.

#import <Cocoa/Cocoa.h>
#include <sys/sysctl.h>
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
// Does this Mac have AltiVec: a G4 or G5 rather than a G3. hw.vectorunit is
// the one that answers on both systems - hw.optional.altivec does not exist
// on Tiger at all, and asking for it there is an error rather than a no.
static BOOL CPHasVectorUnit(void)
{
    int vector = 0;
    size_t size = sizeof vector;

    if (sysctlbyname("hw.vectorunit", &vector, &size, NULL, 0) != 0)
        return NO;      // too old to be asked is too old to have one
    return vector != 0;
}

// Only when the engine is one this system can run. Pointing Tiger at a
// Leopard engine would stop the browser launching at all, which is worse
// than the system WebKit it would otherwise fall back to; each engine says
// what it needs in its own Info.plist (package-webkit.sh writes it), and an
// engine that says nothing is assumed to need Leopard, which is what every
// build before this one was.
static void CPUseBundledEngine(int argc, const char *argv[])
{
    // Best first: the Leopard engine is built for the G4 with AltiVec and
    // has WebGL and Web Audio; the Tiger one is the G3 baseline without
    // them. A Mac takes the first it can run.
    static NSString * const folders[] = { @"Frameworks", @"Frameworks-10.4", nil };
    char executable[MAXPATHLEN], resolved[MAXPATHLEN];
    uint32_t size = sizeof executable;
    NSAutoreleasePool *pool;
    NSString *contents, *current;
    unsigned index;

    if (getenv("CP_ENGINE_CHOSEN") != NULL)
        return;     // this is the second time through
    if (_NSGetExecutablePath(executable, &size) != 0 || realpath(executable, resolved) == NULL)
        return;

    pool = [[NSAutoreleasePool alloc] init];
    // .../Captain Polliwog.app/Contents/MacOS/CaptainPolliwog -> .../Contents
    contents = [[[NSString stringWithUTF8String:resolved]
                    stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    current = getenv("DYLD_FRAMEWORK_PATH") != NULL
        ? [NSString stringWithUTF8String:getenv("DYLD_FRAMEWORK_PATH")] : nil;

    for (index = 0; folders[index] != nil; index++) {
        NSString *frameworks = [contents stringByAppendingPathComponent:folders[index]];
        NSDictionary *engineInfo = [NSDictionary dictionaryWithContentsOfFile:
            [frameworks stringByAppendingPathComponent:@"WebKit.framework/Resources/Info.plist"]];
        NSString *minimum = [engineInfo objectForKey:@"LSMinimumSystemVersion"];
        id needsVector = [engineInfo objectForKey:@"CPRequiresVectorUnit"];

        if (engineInfo == nil)
            continue;
        if (minimum == nil)
            minimum = @"10.5";
        if (!CPSystemIsAtLeast(minimum))
            continue;
        // A G4 build uses instructions a G3 has not got, so on a G3 it does
        // not run slowly, it does not run. The G3 build runs on both, and is
        // what a Mac without a vector unit is given whatever system it has -
        // which is also what a G3 running Leopard needs, and what it would
        // not have been given before this.
        if (needsVector != nil && [needsVector boolValue] && !CPHasVectorUnit())
            continue;
        if (current != nil && [current rangeOfString:frameworks].location != NSNotFound)
            break;      // already running with this one

        setenv("DYLD_FRAMEWORK_PATH", [frameworks fileSystemRepresentation], 1);
        setenv("CP_ENGINE_CHOSEN", "1", 1);
        execv(resolved, (char * const *)argv);
        // Only reached if exec failed; carry on with whatever loaded.
        break;
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
