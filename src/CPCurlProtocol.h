/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

@class CPNetworkTask;

// Registering this class puts Captain Polliwog's own TLS in front of the one
// built into Tiger and Leopard, which stops at TLS 1.0 and cannot reach most
// sites any more. WebKit loads through Foundation, so everything it fetches
// comes through here.
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
