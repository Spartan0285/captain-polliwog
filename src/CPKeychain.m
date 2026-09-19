/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPKeychain.h"
#include <Security/Security.h>

// Captain Polliwog's own items (cards) are generic passwords with this
// service name.
#define CPCardService "Captain Polliwog Card"

// "Any", as 0: the named constants arrived with the 10.5 SDK.
#define CPAnyProtocol ((SecProtocolType)0)
#define CPAnyAuthentication ((SecAuthenticationType)0)

static NSString *CPStringFromAttribute(SecKeychainAttribute *attribute)
{
    if (attribute == NULL || attribute->data == NULL || !attribute->length)
        return nil;
    return [[[NSString alloc] initWithBytes:attribute->data length:attribute->length encoding:NSUTF8StringEncoding] autorelease];
}

// Calls block-less C back: each item of a class, with its account and
// server (or service) attributes.
typedef void (*CPItemVisitor)(SecKeychainItemRef item, NSString *account, NSString *server, void *context);

static void CPVisitItems(SecItemClass itemClass, const char *server, UInt32 serverTag, CPItemVisitor visitor, void *context)
{
    SecKeychainAttribute searchAttribute;
    SecKeychainAttributeList searchList;
    SecKeychainSearchRef search = NULL;
    SecKeychainItemRef item = NULL;
    UInt32 tags[2] = { kSecAccountItemAttr, serverTag };
    UInt32 formats[2] = { CSSM_DB_ATTRIBUTE_FORMAT_STRING, CSSM_DB_ATTRIBUTE_FORMAT_STRING };
    SecKeychainAttributeInfo info = { 2, tags, formats };

    searchList.count = 0;
    searchList.attr = &searchAttribute;
    if (server != NULL) {
        searchAttribute.tag = serverTag;
        searchAttribute.length = strlen(server);
        searchAttribute.data = (void *)server;
        searchList.count = 1;
    }
    if (SecKeychainSearchCreateFromAttributes(NULL, itemClass, &searchList, &search) != noErr)
        return;
    while (SecKeychainSearchCopyNext(search, &item) == noErr) {
        SecKeychainAttributeList *attributes = NULL;
        if (SecKeychainItemCopyAttributesAndData(item, &info, NULL, &attributes, NULL, NULL) == noErr) {
            visitor(item, CPStringFromAttribute(&attributes->attr[0]), CPStringFromAttribute(&attributes->attr[1]), context);
            SecKeychainItemFreeAttributesAndData(attributes, NULL);
        }
        CFRelease(item);
    }
    CFRelease(search);
}

static void CPCollectAccount(SecKeychainItemRef item, NSString *account, NSString *server, void *context)
{
    if ([account length] && ![(NSMutableArray *)context containsObject:account])
        [(NSMutableArray *)context addObject:account];
}

static void CPCollectLogin(SecKeychainItemRef item, NSString *account, NSString *server, void *context)
{
    if ([account length] && [server length])
        [(NSMutableArray *)context addObject:[NSDictionary dictionaryWithObjectsAndKeys:server, @"host", account, @"account", nil]];
}

// The host, and without its "www." (or with it): Safari saves either.
static NSArray *CPHostVariants(NSString *host)
{
    host = [host lowercaseString];
    if ([host hasPrefix:@"www."])
        return [NSArray arrayWithObjects:host, [host substringFromIndex:4], nil];
    return [NSArray arrayWithObjects:host, [@"www." stringByAppendingString:host], nil];
}

static SecKeychainItemRef CPCopyLoginItem(NSString *host, NSString *account)
{
    SecKeychainItemRef item = NULL;
    const char *server = [host UTF8String], *name = [account UTF8String];
    if (SecKeychainFindInternetPassword(NULL, strlen(server), server, 0, NULL, strlen(name), name, 0, NULL, 0,
                                        CPAnyProtocol, CPAnyAuthentication, NULL, NULL, &item) != noErr)
        return NULL;
    return item;
}

@implementation CPKeychain

+ (NSArray *)accountsForHost:(NSString *)host
{
    NSMutableArray *accounts = [NSMutableArray array];
    NSArray *variants = CPHostVariants(host);
    unsigned i;
    for (i = 0; i < [variants count]; i++)
        CPVisitItems(kSecInternetPasswordItemClass, [[variants objectAtIndex:i] UTF8String], kSecServerItemAttr, CPCollectAccount, accounts);
    return accounts;
}

+ (NSString *)passwordForHost:(NSString *)host account:(NSString *)account
{
    NSArray *variants = CPHostVariants(host);
    unsigned i;
    for (i = 0; i < [variants count]; i++) {
        const char *server = [[variants objectAtIndex:i] UTF8String], *name = [account UTF8String];
        UInt32 length = 0;
        void *data = NULL;
        // For a password another application saved, the Mac asks first.
        if (SecKeychainFindInternetPassword(NULL, strlen(server), server, 0, NULL, strlen(name), name, 0, NULL, 0,
                                            CPAnyProtocol, CPAnyAuthentication, &length, &data, NULL) == noErr) {
            NSString *password = [[[NSString alloc] initWithBytes:data length:length encoding:NSUTF8StringEncoding] autorelease];
            SecKeychainItemFreeContent(NULL, data);
            return password;
        }
    }
    return nil;
}

+ (BOOL)savePassword:(NSString *)password forHost:(NSString *)host account:(NSString *)account
{
    const char *secret = [password UTF8String];
    SecKeychainItemRef item = CPCopyLoginItem([host lowercaseString], account);
    OSStatus status;

    if (item != NULL) {
        status = SecKeychainItemModifyAttributesAndData(item, NULL, strlen(secret), secret);
        CFRelease(item);
        return status == noErr;
    }
    {
        const char *server = [[host lowercaseString] UTF8String], *name = [account UTF8String];
        // As Safari saves them, so each browser finds the other's.
        status = SecKeychainAddInternetPassword(NULL, strlen(server), server, 0, NULL, strlen(name), name, 0, "",
                                                0, kSecProtocolTypeHTTPS, kSecAuthenticationTypeHTMLForm,
                                                strlen(secret), secret, NULL);
    }
    return status == noErr;
}

+ (NSArray *)allLogins
{
    NSMutableArray *logins = [NSMutableArray array];
    CPVisitItems(kSecInternetPasswordItemClass, NULL, kSecServerItemAttr, CPCollectLogin, logins);
    return logins;
}

+ (void)removeLoginForHost:(NSString *)host account:(NSString *)account
{
    SecKeychainItemRef item = CPCopyLoginItem(host, account);
    if (item != NULL) {
        SecKeychainItemDelete(item);
        CFRelease(item);
    }
}

static void CPCollectCardItem(SecKeychainItemRef item, NSString *account, NSString *service, void *context)
{
    UInt32 length = 0;
    void *data = NULL;
    NSDictionary *card;
    if (![service isEqualToString:@CPCardService])
        return;
    if (SecKeychainItemCopyContent(item, NULL, NULL, &length, &data) != noErr)
        return;
    card = [NSPropertyListSerialization propertyListFromData:[NSData dataWithBytes:data length:length]
                                            mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
    SecKeychainItemFreeContent(NULL, data);
    if ([card isKindOfClass:[NSDictionary class]])
        [(NSMutableArray *)context addObject:card];
}

+ (NSArray *)cards
{
    NSMutableArray *cards = [NSMutableArray array];
    CPVisitItems(kSecGenericPasswordItemClass, CPCardService, kSecServiceItemAttr, CPCollectCardItem, cards);
    return cards;
}

static SecKeychainItemRef CPCopyCardItem(NSString *label)
{
    SecKeychainItemRef item = NULL;
    const char *name = [label UTF8String];
    if (SecKeychainFindGenericPassword(NULL, strlen(CPCardService), CPCardService, strlen(name), name, NULL, NULL, &item) != noErr)
        return NULL;
    return item;
}

+ (void)saveCard:(NSDictionary *)card
{
    NSMutableDictionary *stored = [NSMutableDictionary dictionaryWithDictionary:card];
    NSData *data;
    NSString *label = [card objectForKey:@"label"];
    SecKeychainItemRef item;
    const char *name;

    // Never the security code, whatever a caller passes.
    [stored removeObjectForKey:@"cvv"];
    [stored removeObjectForKey:@"csc"];
    data = [NSPropertyListSerialization dataFromPropertyList:stored format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
    if (data == nil || ![label length])
        return;
    item = CPCopyCardItem(label);
    if (item != NULL) {
        SecKeychainItemModifyAttributesAndData(item, NULL, [data length], [data bytes]);
        CFRelease(item);
        return;
    }
    name = [label UTF8String];
    SecKeychainAddGenericPassword(NULL, strlen(CPCardService), CPCardService, strlen(name), name, [data length], [data bytes], NULL);
}

+ (void)removeCardWithLabel:(NSString *)label
{
    SecKeychainItemRef item = CPCopyCardItem(label);
    if (item != NULL) {
        SecKeychainItemDelete(item);
        CFRelease(item);
    }
}

@end
