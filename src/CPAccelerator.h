/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// PowerEmu's Web Accelerator (docs/POWEREMU_WEB_ACCELERATOR.md): when a
// PowerEmu is reachable, CPNetworkTask sends its requests there, and PowerEmu
// fetches them with a modern Mac's networking, converting images the engine
// can't decode, scaling large ones down, and answering ad and tracker
// requests with nothing.
//
// Inside a PowerEmu virtual Mac it is always at 10.0.2.100:7780 and needs no
// pairing. A real Mac finds it with Bonjour and uses it only once the user
// has entered the pairing code PowerEmu shows: that hop is plain HTTP, so it
// is an explicit choice.
//
// Everything here is thread-safe: the network thread asks +shouldRoute: for
// every request.

extern NSString * const CPAcceleratorStatusDidChangeNotification;

@interface CPAccelerator : NSObject

// At launch, and when the preference or pairing code changes.
+ (void)start;

// "Automatic" (the default) or "Off".
+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;

// The pairing code for a PowerEmu on the network, kept in the Keychain.
+ (NSString *)pairingCode;
+ (void)setPairingCode:(NSString *)code;

// Whether this request should go through PowerEmu now.
+ (BOOL)shouldRoute:(NSURL *)url;
// The accelerator's address ("http://10.0.2.100:7780/"), or nil.
+ (NSString *)baseURL;
// Header values for a routed request.
+ (NSString *)engineHeader;
+ (NSString *)token;

// PowerEmu couldn't be reached: stop routing for a minute, then look again.
+ (void)markFailed;
// PowerEmu refused the pairing code.
+ (void)markPairingRejected;

// For the preferences: "Using PowerEmu on Adam's MacBook Air", "PowerEmu not
// found", ...
+ (NSString *)statusDescription;
+ (BOOL)needsPairingCode;

@end
