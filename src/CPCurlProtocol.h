/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPNetworkTask;

// Registering this class puts Captain Polliwog's own network stack in front
// of the one built into Tiger and Leopard: for https, whose TLS stops at 1.0
// and cannot reach most sites any more, and for http, whose IPv6-first
// connections stall for fifteen seconds on networks without IPv6. WebKit loads
// through Foundation, so everything it fetches comes through here.
@interface CPCurlProtocol : NSURLProtocol
{
    CPNetworkTask *task;
}
@end

// NSHTTPURLResponse only became directly creatable in Mac OS X 10.7, so
// responses are built by subclassing it.
@interface CPHTTPURLResponse : NSHTTPURLResponse
{
    int           responseStatusCode;
    NSDictionary *responseHeaderFields;
    NSString     *responseSuggestedFilename;
}

- (id)initWithURL:(NSURL *)aURL
       statusCode:(int)aStatusCode
     headerFields:(NSDictionary *)fields
         MIMEType:(NSString *)MIMEType
    contentLength:(long long)contentLength
     textEncoding:(NSString *)encoding
 suggestedFilename:(NSString *)filename;

@end
