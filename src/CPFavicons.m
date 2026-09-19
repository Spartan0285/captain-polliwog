/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPFavicons.h"
#import <WebKit/WebKit.h>

static NSMutableDictionary *CPIcons = nil;        // site -> NSImage
static NSMutableDictionary *CPIconData = nil;     // site -> PNG data

// The page's icon links, best first: sized 16 or 32, PNG or ICO; never SVG,
// which these engines' image decoders can't draw.
static NSString *CPIconScript =
    @"(function(){var links=document.querySelectorAll('link[rel~=icon],link[rel~=\"shortcut\"],link[rel~=apple-touch-icon]'),r=[];"
    @"for(var i=0;i<links.length;i++){var l=links[i],t=(l.type||'').toLowerCase(),h=l.href||'';"
    @"if(!h||/svg/.test(t)||/\\.svg(\\?|$)/i.test(h))continue;var s=(l.getAttribute('sizes')||'').toLowerCase(),score=0;"
    @"if(/(^| )(16x16|32x32)( |$)/.test(s))score+=4;if(/png|icon/.test(t)||/\\.(png|ico)(\\?|$)/i.test(h))score+=2;"
    @"if(/apple-touch/.test(l.rel))score-=1;r.push([score,h]);}"
    @"r.sort(function(a,b){return b[0]-a[0]});return r.map(function(x){return x[1]}).join('\\n')})()";

static NSString *CPSiteOf(NSURL *url)
{
    NSString *host = [[url host] lowercaseString];
    return [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
}

@interface CPFaviconLoad : NSObject
{
    NSMutableArray *candidates;
    NSString *site;
    id target;
    SEL action;
    NSURLConnection *connection;
    NSMutableData *data;
    NSString *userAgent;
    NSString *referrer;
}
- (id)initWithCandidates:(NSArray *)urls site:(NSString *)aSite target:(id)aTarget action:(SEL)anAction;
- (void)setUserAgent:(NSString *)agent referrer:(NSString *)page;
- (void)tryNext;
@end

@implementation CPFaviconLoad

- (id)initWithCandidates:(NSArray *)urls site:(NSString *)aSite target:(id)aTarget action:(SEL)anAction
{
    self = [super init];
    if (self == nil)
        return nil;
    candidates = [urls mutableCopy];
    site = [aSite copy];
    target = [aTarget retain];
    action = anAction;
    return self;
}

- (void)setUserAgent:(NSString *)agent referrer:(NSString *)page
{
    [userAgent release];
    userAgent = [agent copy];
    [referrer release];
    referrer = [page copy];
}

- (void)dealloc
{
    [userAgent release];
    [referrer release];
    [candidates release];
    [site release];
    [target release];
    [connection release];
    [data release];
    [super dealloc];
}

- (void)finishWithImage:(NSImage *)image
{
    if (image != nil) {
        [CPIcons setObject:image forKey:site];
        [CPIconData setObject:[[NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]]
                               representationUsingType:NSPNGFileType properties:[NSDictionary dictionary]]
                       forKey:site];
    }
    [target performSelector:action withObject:image];
    [self autorelease];
}

- (void)tryNext
{
    NSURL *url;
    [connection release];
    connection = nil;
    [data release];
    data = [[NSMutableData alloc] init];
    if (![candidates count]) {
        [self finishWithImage:nil];
        return;
    }
    url = [NSURL URLWithString:[candidates objectAtIndex:0]];
    [candidates removeObjectAtIndex:0];
    if (url == nil) {
        [self tryNext];
        return;
    }
    {
        // As the page's own requests look: some sites refuse others.
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        if (userAgent != nil)
            [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
        if (referrer != nil)
            [request setValue:referrer forHTTPHeaderField:@"Referer"];
        [request setValue:@"image/png,image/x-icon,image/*;q=0.8,*/*;q=0.5" forHTTPHeaderField:@"Accept"];
        connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    }
}

- (void)connection:(NSURLConnection *)aConnection didReceiveResponse:(NSURLResponse *)response
{
    if ([response respondsToSelector:@selector(statusCode)] && [(NSHTTPURLResponse *)response statusCode] >= 400) {
        [aConnection cancel];
        [self tryNext];
    }
}

- (void)connection:(NSURLConnection *)aConnection didReceiveData:(NSData *)more
{
    [data appendData:more];
    // No icon is this big; something else is being served.
    if ([data length] > 256 * 1024) {
        [aConnection cancel];
        [self tryNext];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection
{
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    if (image == nil || [image size].width < 1.0f) {
        [self tryNext];
        return;
    }
    // The smallest representation that is still 16 points or more.
    [image setScalesWhenResized:YES];
    [image setSize:NSMakeSize(16.0f, 16.0f)];
    [self finishWithImage:image];
}

- (void)connection:(NSURLConnection *)aConnection didFailWithError:(NSError *)error
{
    [self tryNext];
}

@end

@implementation CPFavicons

+ (void)initialize
{
    if (CPIcons == nil) {
        CPIcons = [[NSMutableDictionary alloc] init];
        CPIconData = [[NSMutableDictionary alloc] init];
    }
}

+ (NSImage *)iconForURL:(NSURL *)url
{
    NSString *site = CPSiteOf(url);
    return site != nil ? [CPIcons objectForKey:site] : nil;
}

+ (NSString *)dataURLForURL:(NSURL *)url
{
    NSString *site = CPSiteOf(url);
    NSData *png = site != nil ? [CPIconData objectForKey:site] : nil;
    const unsigned char *bytes;
    static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    NSMutableString *result;
    unsigned i, length;

    if (png == nil)
        return nil;
    bytes = [png bytes];
    length = [png length];
    result = [NSMutableString stringWithString:@"data:image/png;base64,"];
    for (i = 0; i < length; i += 3) {
        unsigned value = bytes[i] << 16 | (i + 1 < length ? bytes[i + 1] << 8 : 0) | (i + 2 < length ? bytes[i + 2] : 0);
        [result appendFormat:@"%c%c%c%c", table[(value >> 18) & 63], table[(value >> 12) & 63],
         i + 1 < length ? table[(value >> 6) & 63] : '=', i + 2 < length ? table[value & 63] : '='];
    }
    return result;
}

+ (void)loadIconForPage:(WebView *)webView URL:(NSURL *)url target:(id)target action:(SEL)action
{
    NSString *site = CPSiteOf(url);
    NSString *scheme = [[url scheme] lowercaseString];
    NSMutableArray *candidates;
    NSString *found;
    NSImage *known;

    if (site == nil || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]))
        return;
    known = [CPIcons objectForKey:site];
    if (known != nil) {
        [target performSelector:action withObject:known];
        return;
    }
    // Scripts may be off: then only the site's /favicon.ico.
    found = [webView stringByEvaluatingJavaScriptFromString:CPIconScript];
    candidates = [NSMutableArray arrayWithArray:([found length] ? [found componentsSeparatedByString:@"\n"] : [NSArray array])];
    [candidates addObject:[NSString stringWithFormat:@"%@://%@/favicon.ico", scheme, [url host]]];
    {
        CPFaviconLoad *load = [[CPFaviconLoad alloc] initWithCandidates:candidates site:site target:target action:action];
        [load setUserAgent:[webView userAgentForURL:url] referrer:[url absoluteString]];
        [load tryNext];
    }
}

@end
