/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPStartPage.h"

#import "CPSettings.h"
#import "CPBookmarks.h"
#import "CPHistory.h"
#import "CPFavicons.h"
#import <WebKit/WebKit.h>

#define CPTopSiteCount 12

static NSString *CPStartStyle =
    @"body { margin: 0; background: #f2f2f4; font: 13px 'Lucida Grande', Helvetica, sans-serif; color: #333; }\n"
    @".cp-start { max-width: 760px; margin: 0 auto; padding: 36px 24px; }\n"
    @"form { text-align: center; margin: 0 0 28px; }\n"
    @"input[type=text] { width: 60%; font-size: 15px; padding: 5px 8px; border: 1px solid #bbb; border-radius: 6px; }\n"
    @"h2 { font-size: 15px; margin: 22px 0 10px; color: #444; }\n"
    @".cp-tiles { overflow: hidden; }\n"
    @".cp-tile { float: left; width: 96px; height: 92px; margin: 0 10px 12px 0; text-align: center; text-decoration: none; color: #333; }\n"
    @".cp-icon { display: block; width: 56px; height: 56px; margin: 0 auto 6px; background: #fff; border-radius: 12px; "
    @"border: 1px solid #ddd; line-height: 56px; font: bold 24px/56px Helvetica, sans-serif; color: #999; }\n"
    @".cp-icon img { width: 32px; height: 32px; margin-top: 12px; }\n"
    @".cp-name { display: block; font-size: 11px; line-height: 13px; height: 26px; overflow: hidden; }\n"
    @".cp-empty { color: #888; font-size: 12px; }\n";

static NSString *CPEscape(NSString *text)
{
    NSMutableString *result = [NSMutableString stringWithString:(text != nil ? text : @"")];
    [result replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, [result length])];
    return result;
}

static NSString *CPSiteOf(NSString *URLString)
{
    NSString *host = [[[NSURL URLWithString:URLString] host] lowercaseString];
    return [host hasPrefix:@"www."] ? [host substringFromIndex:4] : host;
}

static void CPAppendTile(NSMutableString *html, NSString *title, NSString *URLString)
{
    NSURL *url = [NSURL URLWithString:URLString];
    NSString *icon = [CPFavicons dataURLForURL:url];
    NSString *site = CPSiteOf(URLString);
    NSString *letter = [site length] ? [[site substringToIndex:1] uppercaseString] : @"?";
    [html appendFormat:@"<a class=\"cp-tile\" href=\"%@\" title=\"%@\"><span class=\"cp-icon\">%@</span><span class=\"cp-name\">%@</span></a>",
     CPEscape(URLString), CPEscape(URLString),
     icon != nil ? [NSString stringWithFormat:@"<img src=\"%@\" alt=\"\">", icon] : CPEscape(letter),
     CPEscape([title length] ? title : site)];
}

@implementation CPStartPage

+ (NSString *)HTML
{
    NSMutableString *html = [NSMutableString string];
    NSArray *favorites = [[[CPBookmarkStore sharedStore] favoritesFolder] children];
    NSArray *recent = [[CPHistory sharedHistory] recentItems:600];
    NSMutableDictionary *visits = [NSMutableDictionary dictionary], *examples = [NSMutableDictionary dictionary];
    NSMutableSet *favoriteSites = [NSMutableSet set];
    NSArray *ranked;
    unsigned i, shown;

    [html appendFormat:@"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Start Page</title><style>%@</style></head><body><div class=\"cp-start\">", CPStartStyle];
    [html appendString:@"<form action=\"https://lite.duckduckgo.com/lite/\" method=\"get\"><input type=\"text\" name=\"q\" placeholder=\"Search\" autofocus></form>"];

    [html appendString:@"<h2>Favorites</h2><div class=\"cp-tiles\">"];
    for (i = 0; i < [favorites count]; i++) {
        CPBookmark *favorite = [favorites objectAtIndex:i];
        if ([favorite isFolder])
            continue;
        CPAppendTile(html, [favorite title], [favorite URLString]);
        if (CPSiteOf([favorite URLString]) != nil)
            [favoriteSites addObject:CPSiteOf([favorite URLString])];
    }
    if (![favorites count])
        [html appendString:@"<p class=\"cp-empty\">Click the star in the address bar to add a page here.</p>"];
    [html appendString:@"</div>"];

    // Top Sites: each site's visits, lately.
    for (i = 0; i < [recent count]; i++) {
        WebHistoryItem *item = [recent objectAtIndex:i];
        NSString *site = CPSiteOf([item URLString]);
        int count = [item respondsToSelector:@selector(visitCount)] ? (int)[item performSelector:@selector(visitCount)] : 1;
        if (site == nil || [favoriteSites containsObject:site])
            continue;
        [visits setObject:[NSNumber numberWithInt:[[visits objectForKey:site] intValue] + MAX(count, 1)] forKey:site];
        if ([examples objectForKey:site] == nil) {
            NSURL *url = [NSURL URLWithString:[item URLString]];
            NSString *home = [NSString stringWithFormat:@"%@://%@/", [url scheme], [url host]];
            [examples setObject:[NSArray arrayWithObjects:home, ([[item title] length] ? [item title] : site), nil] forKey:site];
        }
    }
    ranked = [visits keysSortedByValueUsingSelector:@selector(compare:)];
    if ([ranked count] && [[CPSettings sharedSettings] showsTopSites]) {
        [html appendString:@"<h2>Top Sites</h2><div class=\"cp-tiles\">"];
        for (i = [ranked count], shown = 0; i > 0 && shown < CPTopSiteCount; i--, shown++) {
            NSArray *example = [examples objectForKey:[ranked objectAtIndex:i - 1]];
            NSString *site = [ranked objectAtIndex:i - 1];
            CPAppendTile(html, site, [example objectAtIndex:0]);
        }
        [html appendString:@"</div>"];
    }
    [html appendString:@"</div></body></html>"];
    return html;
}

@end
