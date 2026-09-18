/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPReader.h"
#import <WebKit/WebKit.h>

// A paragraph shorter than this is not counted as prose.
#define CPMinimumParagraphLength 25
// Nor an article shorter than this.
#define CPMinimumArticleLength 140
// How deep the page's markup is followed; real articles are far shallower.
#define CPMaximumDepth 200

// Class and id words that mark page furniture, not the article. From
// Readability, which learned them the hard way.
static NSString *CPUnlikelyWords[] = {
    @"-ad-", @"ai2html", @"banner", @"breadcrumb", @"combx", @"comment", @"community", @"cover-wrap",
    @"disqus", @"extra", @"footer", @"gdpr", @"header", @"legends", @"menu", @"related", @"remark",
    @"replies", @"rss", @"shoutbox", @"sidebar", @"skyscraper", @"social", @"sponsor", @"supplemental",
    @"ad-break", @"agegate", @"pagination", @"pager", @"popup", @"newsletter", @"subscribe", @"cookie",
    @"promo", @"outbrain", @"taboola", @"share", @"recirc", @"signup", @"modal", @"noprint", @"navbox",
    @"metadata", @"ambox", @"editsection", @"catlinks", @"interlanguage", @"language", @"toolbar", nil
};
static NSString *CPMaybeWords[] = { @"and", @"article", @"body", @"column", @"content", @"main", @"shadow", nil };
static NSString *CPPositiveWords[] = {
    @"article", @"body", @"content", @"entry", @"hentry", @"h-entry", @"main", @"page", @"post", @"text",
    @"blog", @"story", nil
};
static NSString *CPNegativeWords[] = {
    @"hidden", @"banner", @"combx", @"comment", @"com-", @"contact", @"foot", @"footer", @"footnote",
    @"masthead", @"media", @"meta", @"outbrain", @"promo", @"related", @"scroll", @"share", @"shoutbox",
    @"sidebar", @"skyscraper", @"sponsor", @"shopping", @"tags", @"tool", @"widget", @"advert", nil
};

static NSString *CPReaderStyle =
    @"body { margin: 0; background: #f7f5ef; color: #222; }\n"
    @".cp-reader { max-width: 38em; margin: 0 auto; padding: 1.5em 1.5em 4em; font: 17px/1.55 Georgia, 'Times New Roman', serif; word-wrap: break-word; }\n"
    @".cp-meta { font: 12px 'Lucida Grande', Helvetica, sans-serif; color: #777; }\n"
    @".cp-meta a { color: #777; }\n"
    @"h1 { font: bold 1.8em/1.2 'Lucida Grande', Helvetica, sans-serif; margin: 0.4em 0 0.3em; }\n"
    @"h2, h3, h4, h5, h6 { font-family: 'Lucida Grande', Helvetica, sans-serif; line-height: 1.3; }\n"
    @"a { color: #1a55a7; }\n"
    @"a.cp-image { display: inline-block; margin: 0.3em 0; }\n"
    @"a.cp-image img { max-width: 50%; max-height: 240px; border: 1px solid #ddd; vertical-align: top; }\n"
    @"figure { margin: 1em 0; }\n"
    @"figcaption { font-size: 0.85em; color: #666; }\n"
    @"pre { white-space: pre-wrap; background: #eee; padding: 0.6em; font: 12px Monaco, monospace; }\n"
    @"code { font: 0.85em Monaco, monospace; }\n"
    @"blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid #ccc; color: #444; }\n"
    @"table { border-collapse: collapse; font-size: 0.9em; display: block; overflow-x: auto; max-width: 100%; }\n"
    @"td, th { border: 1px solid #ccc; padding: 0.3em; }\n";

#pragma mark Reading the page

static BOOL CPIsElement(DOMNode *node)
{
    return [node nodeType] == DOM_ELEMENT_NODE;
}

static NSString *CPTagName(DOMNode *node)
{
    return [[node nodeName] lowercaseString];
}

static NSString *CPAttribute(DOMNode *node, NSString *name)
{
    NSString *value = [(DOMElement *)node getAttribute:name];
    return value != nil ? value : @"";
}

static BOOL CPTagIsOneOf(NSString *tag, NSString *list)
{
    // list is space-separated, with spaces at both ends.
    return [list rangeOfString:[NSString stringWithFormat:@" %@ ", tag]].location != NSNotFound;
}

static BOOL CPContainsWord(NSString *text, NSString **words)
{
    unsigned i;
    for (i = 0; words[i] != nil; i++) {
        if ([text rangeOfString:words[i]].location != NSNotFound)
            return YES;
    }
    return NO;
}

static NSString *CPClassAndID(DOMNode *node)
{
    return [[NSString stringWithFormat:@"%@ %@", CPAttribute(node, @"class"), CPAttribute(node, @"id")] lowercaseString];
}

static BOOL CPIsHidden(DOMNode *node)
{
    NSString *style = [[CPAttribute(node, @"style") lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([(DOMElement *)node hasAttribute:@"hidden"] || [CPAttribute(node, @"aria-hidden") isEqualToString:@"true"])
        return YES;
    return [style rangeOfString:@"display:none"].location != NSNotFound
        || [style rangeOfString:@"display: none"].location != NSNotFound
        || [style rangeOfString:@"visibility:hidden"].location != NSNotFound;
}

static BOOL CPIsUnlikely(DOMNode *node)
{
    NSString *tag = CPTagName(node);
    NSString *words;
    if ([tag isEqualToString:@"body"] || [tag isEqualToString:@"a"] || [tag isEqualToString:@"article"] || [tag isEqualToString:@"main"])
        return NO;
    if (CPTagIsOneOf(tag, @" nav aside footer form "))
        return YES;
    words = CPClassAndID(node);
    return CPContainsWord(words, CPUnlikelyWords) && !CPContainsWord(words, CPMaybeWords);
}

// The text a node holds, as the reader would see it.
static void CPAppendText(DOMNode *node, NSMutableString *text, unsigned depth)
{
    DOMNode *child;
    if ([node nodeType] == DOM_TEXT_NODE) {
        [text appendString:[node nodeValue]];
        return;
    }
    if (!CPIsElement(node) || depth > CPMaximumDepth || CPTagIsOneOf(CPTagName(node), @" script style noscript template svg "))
        return;
    for (child = [node firstChild]; child != nil; child = [child nextSibling])
        CPAppendText(child, text, depth + 1);
}

// Characters of text, with runs of white space counted once.
static unsigned CPTextLength(NSString *text)
{
    unsigned length = [text length], count = 0, i;
    BOOL lastWasSpace = YES;
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (i = 0; i < length; i++) {
        BOOL isSpace = [space characterIsMember:[text characterAtIndex:i]];
        if (!isSpace || !lastWasSpace)
            count++;
        lastWasSpace = isSpace;
    }
    return count;
}

static NSString *CPTextOf(DOMNode *node)
{
    NSMutableString *text = [NSMutableString string];
    CPAppendText(node, text, 0);
    return text;
}

static void CPAddLinkTextLength(DOMNode *node, unsigned *length, unsigned depth)
{
    DOMNode *child;
    if (!CPIsElement(node) || depth > CPMaximumDepth)
        return;
    if ([CPTagName(node) isEqualToString:@"a"]) {
        *length += CPTextLength(CPTextOf(node));
        return;
    }
    for (child = [node firstChild]; child != nil; child = [child nextSibling])
        CPAddLinkTextLength(child, length, depth + 1);
}

// How much of a node's text is links: high for menus and lists of stories.
static float CPLinkDensity(DOMNode *node)
{
    unsigned total = CPTextLength(CPTextOf(node)), links = 0;
    if (!total)
        return 0;
    CPAddLinkTextLength(node, &links, 0);
    return (float)links / (float)total;
}

static int CPClassWeight(DOMNode *node)
{
    NSString *words = CPClassAndID(node);
    int weight = 0;
    if (CPContainsWord(words, CPNegativeWords))
        weight -= 25;
    if (CPContainsWord(words, CPPositiveWords))
        weight += 25;
    return weight;
}

static float CPInitialScore(DOMNode *node)
{
    NSString *tag = CPTagName(node);
    float score = CPClassWeight(node);
    if ([tag isEqualToString:@"div"])
        score += 5;
    else if (CPTagIsOneOf(tag, @" pre td blockquote "))
        score += 3;
    else if (CPTagIsOneOf(tag, @" address ol ul dl dd dt li form "))
        score -= 3;
    else if (CPTagIsOneOf(tag, @" h1 h2 h3 h4 h5 h6 th "))
        score -= 5;
    return score;
}

// A div holding only text and inline markup reads as a paragraph.
static BOOL CPIsParagraphLikeDiv(DOMNode *node)
{
    DOMNode *child;
    for (child = [node firstChild]; child != nil; child = [child nextSibling]) {
        if (CPIsElement(child) && CPTagIsOneOf(CPTagName(child), @" p div table ul ol pre blockquote h1 h2 h3 h4 h5 h6 section article figure dl "))
            return NO;
    }
    return YES;
}

static void CPCollectParagraphs(DOMNode *node, NSMutableArray *paragraphs, unsigned depth)
{
    DOMNode *child;
    NSString *tag;
    if (!CPIsElement(node) || depth > CPMaximumDepth)
        return;
    tag = CPTagName(node);
    if (CPTagIsOneOf(tag, @" script style noscript template svg iframe "))
        return;
    if (depth > 0 && (CPIsHidden(node) || CPIsUnlikely(node)))
        return;
    if (CPTagIsOneOf(tag, @" p pre td ") || ([tag isEqualToString:@"div"] && CPIsParagraphLikeDiv(node))) {
        [paragraphs addObject:node];
        if (![tag isEqualToString:@"td"])
            return;
    }
    for (child = [node firstChild]; child != nil; child = [child nextSibling])
        CPCollectParagraphs(child, paragraphs, depth + 1);
}

static unsigned CPIndexOfNode(NSArray *nodes, DOMNode *node)
{
    return [nodes indexOfObjectIdenticalTo:node];
}

static void CPAddScore(NSMutableArray *candidates, NSMutableArray *scores, DOMNode *node, float amount)
{
    unsigned index;
    if (node == nil || !CPIsElement(node))
        return;
    index = CPIndexOfNode(candidates, node);
    if (index == NSNotFound) {
        [candidates addObject:node];
        [scores addObject:[NSNumber numberWithFloat:CPInitialScore(node) + amount]];
        return;
    }
    [scores replaceObjectAtIndex:index withObject:[NSNumber numberWithFloat:[[scores objectAtIndex:index] floatValue] + amount]];
}

static float CPScoreOf(NSArray *candidates, NSArray *scores, DOMNode *node)
{
    unsigned index = CPIndexOfNode(candidates, node);
    return index == NSNotFound ? 0 : [[scores objectAtIndex:index] floatValue];
}

static NSString *CPMetaContent(DOMDocument *document, NSString *key)
{
    DOMNodeList *metas = [document getElementsByTagName:@"meta"];
    unsigned i, count = [metas length];
    for (i = 0; i < count; i++) {
        DOMNode *meta = [metas item:i];
        if ([CPAttribute(meta, @"property") isEqualToString:key] || [CPAttribute(meta, @"name") isEqualToString:key]) {
            NSString *content = [CPAttribute(meta, @"content") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([content length])
                return content;
        }
    }
    return nil;
}

#pragma mark Writing the reader page

static NSString *CPEscape(NSString *text)
{
    NSMutableString *result = [NSMutableString stringWithString:(text != nil ? text : @"")];
    [result replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, [result length])];
    [result replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, [result length])];
    return result;
}

// An address from the page made absolute, if it is one worth linking to.
static NSURL *CPResolvedURL(NSString *value, NSURL *base, BOOL allowData)
{
    NSURL *url;
    NSString *scheme;
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![value length])
        return nil;
    if ([value hasPrefix:@"data:"])
        return allowData && [value length] < 60000 ? [NSURL URLWithString:value] : nil;
    url = [NSURL URLWithString:value relativeToURL:base];
    if (url == nil) {
        NSString *escaped = [value stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        url = escaped != nil ? [NSURL URLWithString:escaped relativeToURL:base] : nil;
    }
    url = [url absoluteURL];
    scheme = [[url scheme] lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"mailto"])
        return nil;
    return url;
}

// A srcset's candidates, smallest first: URLs with their widths (0 when a
// candidate gives a density, not a width).
static NSArray *CPSrcsetCandidates(NSString *srcset)
{
    NSMutableArray *candidates = [NSMutableArray array];
    NSScanner *scanner = [NSScanner scannerWithString:srcset];
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableCharacterSet *separators = [[[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy] autorelease];
    [separators addCharactersInString:@","];
    [scanner setCharactersToBeSkipped:nil];
    while (![scanner isAtEnd]) {
        NSString *url = nil, *descriptor = nil;
        int width = 0;
        [scanner scanCharactersFromSet:separators intoString:NULL];
        if (![scanner scanUpToCharactersFromSet:space intoString:&url])
            break;
        if ([url hasSuffix:@","])
            url = [url substringToIndex:[url length] - 1];
        else {
            [scanner scanCharactersFromSet:space intoString:NULL];
            [scanner scanUpToString:@"," intoString:&descriptor];
            if ([descriptor hasSuffix:@"w"])
                width = [descriptor intValue];
        }
        [candidates addObject:[NSArray arrayWithObjects:url, [NSNumber numberWithInt:width], nil]];
    }
    return candidates;
}

static void CPAppendImage(NSMutableString *out, DOMNode *image, NSURL *base, BOOL insideLink)
{
    NSString *source = nil, *full = nil, *alt;
    NSString *srcset = CPAttribute(image, @"data-srcset");
    NSArray *candidates;
    NSURL *sourceURL, *fullURL;
    int width = [CPAttribute(image, @"width") intValue], height = [CPAttribute(image, @"height") intValue];

    // Pages that load images as they scroll keep the real address aside.
    if ([CPAttribute(image, @"data-src") length])
        source = CPAttribute(image, @"data-src");
    else if ([CPAttribute(image, @"data-lazy-src") length])
        source = CPAttribute(image, @"data-lazy-src");
    else if ([CPAttribute(image, @"data-original") length])
        source = CPAttribute(image, @"data-original");
    else
        source = CPAttribute(image, @"src");
    full = source;
    if (![srcset length])
        srcset = CPAttribute(image, @"srcset");
    candidates = CPSrcsetCandidates(srcset);
    if ([candidates count]) {
        // Show the smallest that still reads well; link the largest.
        unsigned i, best = NSNotFound, largest = 0;
        int bestWidth = 0, largestWidth = -1;
        for (i = 0; i < [candidates count]; i++) {
            int candidateWidth = [[[candidates objectAtIndex:i] objectAtIndex:1] intValue];
            if (candidateWidth >= 300 && (best == NSNotFound || candidateWidth < bestWidth)) {
                best = i;
                bestWidth = candidateWidth;
            }
            if (candidateWidth > largestWidth) {
                largest = i;
                largestWidth = candidateWidth;
            }
        }
        if (best != NSNotFound || ![source length])
            source = [[candidates objectAtIndex:(best != NSNotFound ? best : 0)] objectAtIndex:0];
        full = [[candidates objectAtIndex:largest] objectAtIndex:0];
    }

    // Spacers, tracking pixels and icons.
    if ((width > 0 && width <= 40) || (height > 0 && height <= 40))
        return;
    sourceURL = CPResolvedURL(source, base, YES);
    fullURL = CPResolvedURL(full, base, NO);
    if (sourceURL == nil)
        return;
    alt = CPEscape(CPAttribute(image, @"alt"));
    if (insideLink || fullURL == nil)
        [out appendFormat:@"<img src=\"%@\" alt=\"%@\">", CPEscape([sourceURL absoluteString]), alt];
    else
        [out appendFormat:@"<a class=\"cp-image\" href=\"%@\" title=\"Full size\"><img src=\"%@\" alt=\"%@\"></a>",
         CPEscape([fullURL absoluteString]), CPEscape([sourceURL absoluteString]), alt];
}

typedef struct {
    NSURL *base;
    NSString *title;
    BOOL insideLink;
    BOOL skippedTitle;
} CPWriteState;

static void CPAppendNode(NSMutableString *out, DOMNode *node, CPWriteState *state, unsigned depth)
{
    DOMNode *child;
    NSString *tag;

    if ([node nodeType] == DOM_TEXT_NODE) {
        [out appendString:CPEscape([node nodeValue])];
        return;
    }
    if (!CPIsElement(node) || depth > CPMaximumDepth)
        return;
    tag = CPTagName(node);

    if (CPTagIsOneOf(tag, @" script style noscript template iframe object embed form input button select textarea nav aside footer svg canvas video audio link meta dialog map area "))
        return;
    if (depth > 0 && (CPIsHidden(node) || CPIsUnlikely(node)))
        return;

    if ([tag isEqualToString:@"img"]) {
        CPAppendImage(out, node, state->base, state->insideLink);
        return;
    }
    // Lists, tables and blocks that are mostly links are menus, language
    // lists and related-story boxes: Readability's "clean conditionally".
    if (depth > 0 && CPTagIsOneOf(tag, @" ul ol table div section dl ")) {
        float density = CPLinkDensity(node);
        if (density > 0.5f || (CPTagIsOneOf(tag, @" ul ol ") && density > 0.35f))
            return;
    }
    if ([tag isEqualToString:@"picture"]) {
        DOMNodeList *images = [(DOMElement *)node getElementsByTagName:@"img"];
        if ([images length])
            CPAppendImage(out, [images item:0], state->base, state->insideLink);
        return;
    }
    if ([tag isEqualToString:@"br"] || [tag isEqualToString:@"hr"]) {
        [out appendFormat:@"<%@>", tag];
        return;
    }
    // The page's own heading repeats the title shown above it.
    if ([tag isEqualToString:@"h1"] && !state->skippedTitle) {
        NSString *text = [CPTextOf(node) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([text length] && [state->title rangeOfString:text].location != NSNotFound) {
            state->skippedTitle = YES;
            return;
        }
    }

    if ([tag isEqualToString:@"a"]) {
        NSURL *url = state->insideLink ? nil : CPResolvedURL(CPAttribute(node, @"href"), state->base, NO);
        if (url != nil) {
            [out appendFormat:@"<a href=\"%@\">", CPEscape([url absoluteString])];
            state->insideLink = YES;
        }
        for (child = [node firstChild]; child != nil; child = [child nextSibling])
            CPAppendNode(out, child, state, depth + 1);
        if (url != nil) {
            [out appendString:@"</a>"];
            state->insideLink = NO;
        }
        return;
    }

    // Kept as they are, minus every attribute.
    if (CPTagIsOneOf(tag, @" p h2 h3 h4 h5 h6 ul ol li blockquote pre code em strong b i u s sub sup figure figcaption table thead tbody tfoot tr td th caption dl dt dd cite q small abbr time mark del ins kbd samp var ")) {
        [out appendFormat:@"<%@>", tag];
        for (child = [node firstChild]; child != nil; child = [child nextSibling])
            CPAppendNode(out, child, state, depth + 1);
        [out appendFormat:@"</%@>", tag];
        return;
    }
    if ([tag isEqualToString:@"h1"]) {
        [out appendString:@"<h2>"];
        for (child = [node firstChild]; child != nil; child = [child nextSibling])
            CPAppendNode(out, child, state, depth + 1);
        [out appendString:@"</h2>"];
        return;
    }
    // Other blocks keep their breaks; inline wrappers vanish.
    if (CPTagIsOneOf(tag, @" div section article main header center address details summary ")) {
        [out appendString:@"<div>"];
        for (child = [node firstChild]; child != nil; child = [child nextSibling])
            CPAppendNode(out, child, state, depth + 1);
        [out appendString:@"</div>"];
        return;
    }
    for (child = [node firstChild]; child != nil; child = [child nextSibling])
        CPAppendNode(out, child, state, depth + 1);
}

@implementation CPReader

+ (NSString *)readerHTMLForDocument:(DOMDocument *)document URL:(NSURL *)url
{
    DOMHTMLElement *body;
    NSMutableArray *paragraphs = [NSMutableArray array];
    NSMutableArray *candidates = [NSMutableArray array];
    NSMutableArray *scores = [NSMutableArray array];
    NSMutableArray *parts = [NSMutableArray array];
    NSMutableString *article = [NSMutableString string];
    NSMutableString *html;
    DOMNode *top = nil, *parent, *sibling;
    DOMNodeList *bases;
    NSString *title, *byline, *site;
    NSURL *base = url;
    float topScore = 0, threshold;
    unsigned i, articleLength = 0;
    CPWriteState state;

    if (![document isKindOfClass:[DOMHTMLDocument class]])
        return nil;
    body = [(DOMHTMLDocument *)document body];
    if (body == nil)
        return nil;

    bases = [document getElementsByTagName:@"base"];
    if ([bases length]) {
        NSURL *declared = CPResolvedURL(CPAttribute([bases item:0], @"href"), url, NO);
        if (declared != nil)
            base = declared;
    }

    // Each paragraph of prose scores its container, and half as much its
    // container's container.
    CPCollectParagraphs(body, paragraphs, 0);
    for (i = 0; i < [paragraphs count]; i++) {
        DOMNode *paragraph = [paragraphs objectAtIndex:i];
        NSString *text = CPTextOf(paragraph);
        unsigned length = CPTextLength(text);
        float score;
        if (length < CPMinimumParagraphLength)
            continue;
        score = 1 + [[text componentsSeparatedByString:@","] count] - 1 + MIN(length / 100, 3);
        CPAddScore(candidates, scores, [paragraph parentNode], score);
        if ([paragraph parentNode] != nil)
            CPAddScore(candidates, scores, [[paragraph parentNode] parentNode], score / 2);
    }

    // Containers that are mostly links are menus, not articles.
    for (i = 0; i < [candidates count]; i++) {
        DOMNode *candidate = [candidates objectAtIndex:i];
        float score = [[scores objectAtIndex:i] floatValue] * (1 - CPLinkDensity(candidate));
        [scores replaceObjectAtIndex:i withObject:[NSNumber numberWithFloat:score]];
        if (top == nil || score > topScore) {
            top = candidate;
            topScore = score;
        }
    }
    if (top == nil)
        return nil;

    // The article's other parts sit beside it: more paragraphs, pictures.
    parent = [top parentNode];
    threshold = MAX(10, topScore * 0.2f);
    for (sibling = (parent != nil ? [parent firstChild] : top); sibling != nil; sibling = [sibling nextSibling]) {
        NSString *text;
        unsigned length;
        float density;
        if (!CPIsElement(sibling))
            continue;
        if (sibling == top || CPScoreOf(candidates, scores, sibling) >= threshold) {
            [parts addObject:sibling];
            continue;
        }
        if (![CPTagName(sibling) isEqualToString:@"p"])
            continue;
        text = CPTextOf(sibling);
        length = CPTextLength(text);
        density = CPLinkDensity(sibling);
        if ((length > 80 && density < 0.25f) || (length > 0 && density == 0 && [text rangeOfString:@". "].location != NSNotFound))
            [parts addObject:sibling];
        if (parent == nil)
            break;
    }
    for (i = 0; i < [parts count]; i++)
        articleLength += CPTextLength(CPTextOf([parts objectAtIndex:i]));
    if (articleLength < CPMinimumArticleLength)
        return nil;

    title = CPMetaContent(document, @"og:title");
    if (title == nil)
        title = [(DOMHTMLDocument *)document title];
    {
        // "Article - Site": the page's own heading is the article's title.
        DOMNodeList *headings = [document getElementsByTagName:@"h1"];
        if ([headings length]) {
            NSString *heading = [CPTextOf([headings item:0]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([heading length] > 3 && [title length] > [heading length] && [title rangeOfString:heading].location != NSNotFound)
                title = heading;
        }
    }
    if (![title length])
        title = [url absoluteString];
    byline = CPMetaContent(document, @"author");
    site = CPMetaContent(document, @"og:site_name");
    if (site == nil)
        site = [url host];

    state.base = base;
    state.title = title;
    state.insideLink = NO;
    state.skippedTitle = NO;
    for (i = 0; i < [parts count]; i++)
        CPAppendNode(article, [parts objectAtIndex:i], &state, 0);

    html = [NSMutableString string];
    [html appendString:@"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">"];
    [html appendFormat:@"<title>%@</title><style>%@</style></head><body><div class=\"cp-reader\">", CPEscape(title), CPReaderStyle];
    [html appendFormat:@"<div class=\"cp-meta\">%@ &middot; <a href=\"%@\">Original page</a></div>",
     CPEscape(site), CPEscape([url absoluteString])];
    [html appendFormat:@"<h1>%@</h1>", CPEscape(title)];
    if ([byline length])
        [html appendFormat:@"<div class=\"cp-meta\">%@</div>", CPEscape(byline)];
    [html appendFormat:@"<div class=\"cp-article\">%@</div></div></body></html>", article];
    return html;
}

- (id)initWithDelegate:(id)aDelegate
{
    self = [super init];
    if (self == nil)
        return nil;
    delegate = aDelegate;
    return self;
}

- (void)dealloc
{
    [self cancel];
    [super dealloc];
}

- (void)loadURL:(NSURL *)url userAgent:(NSString *)userAgent
{
    WebPreferences *preferences;

    [self cancel];
    requestedURL = [url retain];
    loaderView = [[WebView alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 800.0f, 600.0f)
                                      frameName:nil
                                      groupName:@"CaptainPolliwogReader"];
    preferences = [[[WebPreferences alloc] initWithIdentifier:@"CaptainPolliwogReader"] autorelease];
    [preferences setAutosaves:NO];
    [preferences setJavaScriptEnabled:NO];
    [preferences setJavaEnabled:NO];
    [preferences setPlugInsEnabled:NO];
    [preferences setLoadsImagesAutomatically:NO];
    [loaderView setPreferences:preferences];
    if (userAgent != nil)
        [loaderView setCustomUserAgent:userAgent];
    [loaderView setFrameLoadDelegate:self];
    [loaderView setResourceLoadDelegate:self];
    [[loaderView mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)cancel
{
    if (loaderView == nil)
        return;
    [loaderView stopLoading:nil];
    [loaderView setFrameLoadDelegate:nil];
    [loaderView setResourceLoadDelegate:nil];
    // -[WebView close] arrived with WebKit 3; Tiger's original WebKit lacks it.
    if ([loaderView respondsToSelector:@selector(close)])
        [loaderView performSelector:@selector(close)];
    [loaderView autorelease];
    loaderView = nil;
    [mainResource release];
    mainResource = nil;
    [requestedURL release];
    requestedURL = nil;
}

- (void)finishWithHTML:(NSString *)html URL:(NSURL *)url
{
    NSURL *requested = [[requestedURL retain] autorelease];
    [self retain];
    [self cancel];
    if ([delegate respondsToSelector:@selector(reader:didMakeHTML:forURL:)])
        [delegate reader:self didMakeHTML:html forURL:(url != nil ? url : requested)];
    [self release];
}

#pragma mark Loading without scripts, images or style sheets

- (id)webView:(WebView *)sender identifierForInitialRequest:(NSURLRequest *)request fromDataSource:(WebDataSource *)dataSource
{
    id identifier = [NSNumber numberWithUnsignedInt:(unsigned)request];
    if (mainResource == nil && dataSource == [[sender mainFrame] provisionalDataSource])
        mainResource = [identifier retain];
    return identifier;
}

- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource
{
    // Only the page itself (and its redirects): no style sheets, frames or
    // anything else a reader leaves out.
    return [identifier isEqual:mainResource] ? request : nil;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    NSURL *url;
    if (frame != [sender mainFrame])
        return;
    url = [[[frame dataSource] response] URL];
    if (url == nil)
        url = requestedURL;
    [self finishWithHTML:[CPReader readerHTMLForDocument:[frame DOMDocument] URL:url] URL:url];
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame == [sender mainFrame])
        [self finishWithHTML:nil URL:nil];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (frame == [sender mainFrame])
        [self finishWithHTML:nil URL:nil];
}

@end
