/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

// Video and audio in web pages play through QuickTime, which fetches them
// with the system's own networking: on Tiger and Leopard that means TLS 1.0,
// which video servers (YouTube's among them) refuse. This relay, a small
// HTTP server on 127.0.0.1, fetches media for QuickTime through the bundled
// libcurl instead, passing Range requests through so seeking works.
//
// Captain Polliwog's engine sends media there when it finds the relay's
// port and token in the registered defaults (CPMediaRelayPort,
// CPMediaRelayToken); the token keeps other programs on the Mac from using
// the relay.
@interface CPMediaRelay : NSObject

+ (void)start;

@end
