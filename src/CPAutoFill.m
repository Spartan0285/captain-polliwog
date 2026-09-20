/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAutoFill.h"
#import "CPKeychain.h"
#import "CPTab.h"
#import "CPPrivateBrowsing.h"
#import "CPDebugSnapshot.h"
#import <WebKit/WebKit.h>
#import <AddressBook/AddressBook.h>
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>

// How long AutoFill stays unlocked after it was last used.
#define CPUnlockIdleTime (10.0 * 60.0)

static NSString *CPAddressKey = @"CPAutoFillAddress";
static NSString *CPNeverSaveKey = @"CPAutoFillNeverSave";

static NSDate *CPUnlockedUntil = nil;
// The login last filled on each host, so saving it again isn't offered.
static NSMutableDictionary *CPFilledLogins = nil;
// Usernames typed on each host's earlier steps, for sign-ins that ask for
// the password on another page.
static NSMutableDictionary *CPTypedUsernames = nil;
// The login last offered for saving, and when: a sign-in that navigates
// twice would otherwise be offered twice.
static NSArray *CPLastOffered = nil;
static NSDate *CPLastOfferedAt = nil;

#pragma mark Talking to the page

// A JavaScript string literal.
static NSString *CPJSString(NSString *text)
{
    NSMutableString *result = [NSMutableString stringWithString:@"\""];
    unsigned i, length = [text length];
    for (i = 0; i < length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '"' || c == '\\')
            [result appendFormat:@"\\%C", c];
        else if (c < 0x20 || c == 0x2028 || c == 0x2029 || c == '<' || c == '>')
            [result appendFormat:@"\\u%04x", c];
        else
            [result appendFormat:@"%C", c];
    }
    [result appendString:@"\""];
    return result;
}

static NSString *CPJSObject(NSDictionary *values)
{
    NSMutableString *result = [NSMutableString stringWithString:@"{"];
    NSEnumerator *keys = [values keyEnumerator];
    NSString *key;
    BOOL first = YES;
    while ((key = [keys nextObject]) != nil) {
        [result appendFormat:@"%@%@: %@", first ? @"" : @", ", CPJSString(key), CPJSString([[values objectForKey:key] description])];
        first = NO;
    }
    [result appendString:@"}"];
    return result;
}

static NSString *CPRunCommand(WebView *webView, NSString *command, NSDictionary *values)
{
    static NSString *script = nil;
    if (script == nil) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"autofill" ofType:@"js"];
        script = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    }
    if (script == nil || webView == nil)
        return nil;
    return [webView stringByEvaluatingJavaScriptFromString:
            [NSString stringWithFormat:@"%@(%@, %@)", script, CPJSString(command), CPJSObject(values != nil ? values : [NSDictionary dictionary])]];
}

static NSArray *CPFieldsOf(NSString *result)
{
    NSArray *fields = [(result != nil ? result : @"") componentsSeparatedByString:[NSString stringWithFormat:@"%C", (unichar)1]];
    return fields;
}

static NSString *CPHost(CPTab *tab)
{
    NSString *scheme = [[[tab URL] scheme] lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])
        return nil;
    return [[[tab URL] host] lowercaseString];
}

// Asks which of up to three choices, or nil if none.
static NSString *CPChoose(NSArray *choices, NSString *message, NSWindow *window)
{
    NSAlert *alert;
    unsigned i, count = MIN([choices count], 3u);
    int answer;
    if ([choices count] == 1)
        return [choices objectAtIndex:0];
    alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:message];
    for (i = 0; i < count; i++)
        [alert addButtonWithTitle:[choices objectAtIndex:i]];
    [alert addButtonWithTitle:@"Cancel"];
    answer = [alert runModal];
    i = answer - NSAlertFirstButtonReturn;
    return i < count ? [choices objectAtIndex:i] : nil;
}

@implementation CPAutoFill

+ (BOOL)unlockWithPrompt:(NSString *)prompt
{
    AuthorizationRef authorization;
    AuthorizationItem right = { "system.privilege.admin", 0, NULL, 0 };
    AuthorizationRights rights = { 1, &right };
    AuthorizationItem promptItem;
    AuthorizationEnvironment environment = { 0, &promptItem };
    const char *promptText = [prompt UTF8String];
    OSStatus status;

    if (CPUnlockedUntil != nil && [CPUnlockedUntil timeIntervalSinceNow] > 0) {
        [CPUnlockedUntil release];
        CPUnlockedUntil = [[NSDate dateWithTimeIntervalSinceNow:CPUnlockIdleTime] retain];
        return YES;
    }
    if (AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authorization) != errAuthorizationSuccess)
        return NO;
    if (promptText != NULL) {
        promptItem.name = kAuthorizationEnvironmentPrompt;
        promptItem.valueLength = strlen(promptText);
        promptItem.value = (void *)promptText;
        promptItem.flags = 0;
        environment.count = 1;
    }
    // The Mac's own password dialog; nothing is done with the rights.
    status = AuthorizationCopyRights(authorization, &rights, &environment,
                                     kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights | kAuthorizationFlagDestroyRights, NULL);
    AuthorizationFree(authorization, kAuthorizationFlagDestroyRights);
    if (status != errAuthorizationSuccess)
        return NO;
    [CPUnlockedUntil release];
    CPUnlockedUntil = [[NSDate dateWithTimeIntervalSinceNow:CPUnlockIdleTime] retain];
    return YES;
}

#pragma mark The address

// A multi-value's primary value, or its first.
static id CPPrimaryValue(ABMultiValue *multi)
{
    int index;
    if (![multi count])
        return nil;
    index = [multi indexForIdentifier:[multi primaryIdentifier]];
    if (index < 0 || (unsigned)index >= [multi count])
        index = 0;
    return [multi valueAtIndex:index];
}

+ (NSDictionary *)addressFromMeCard
{
    return [self addressFromPerson:[[ABAddressBook sharedAddressBook] me]];
}

+ (NSDictionary *)addressFromPerson:(id)person
{
    ABPerson *me = (ABPerson *)person;
    NSMutableDictionary *address = [NSMutableDictionary dictionary];
    ABMultiValue *multi;
    NSDictionary *postal;
    NSString *value;

    if (me == nil)
        return address;
    if ((value = [me valueForProperty:kABFirstNameProperty]) != nil)
        [address setObject:value forKey:@"given-name"];
    if ((value = [me valueForProperty:kABLastNameProperty]) != nil)
        [address setObject:value forKey:@"family-name"];
    if ((value = [me valueForProperty:kABOrganizationProperty]) != nil)
        [address setObject:value forKey:@"organization"];
    if ((value = CPPrimaryValue([me valueForProperty:kABEmailProperty])) != nil)
        [address setObject:value forKey:@"email"];
    if ((value = CPPrimaryValue([me valueForProperty:kABPhoneProperty])) != nil)
        [address setObject:value forKey:@"tel"];
    multi = [me valueForProperty:kABAddressProperty];
    if ([multi count]) {
        NSArray *lines;
        postal = CPPrimaryValue(multi);
        lines = [([postal objectForKey:kABAddressStreetKey] ?: @"") componentsSeparatedByString:@"\n"];
        if ([lines count] && [[lines objectAtIndex:0] length])
            [address setObject:[lines objectAtIndex:0] forKey:@"address-line1"];
        if ([lines count] > 1)
            [address setObject:[[lines subarrayWithRange:NSMakeRange(1, [lines count] - 1)] componentsJoinedByString:@", "] forKey:@"address-line2"];
        if ((value = [postal objectForKey:kABAddressCityKey]) != nil)
            [address setObject:value forKey:@"address-level2"];
        if ((value = [postal objectForKey:kABAddressStateKey]) != nil)
            [address setObject:value forKey:@"address-level1"];
        if ((value = [postal objectForKey:kABAddressZIPKey]) != nil)
            [address setObject:value forKey:@"postal-code"];
        if ((value = [postal objectForKey:kABAddressCountryKey]) != nil)
            [address setObject:value forKey:@"country"];
    }
    return address;
}

+ (NSDictionary *)address
{
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:CPAddressKey];
    return saved != nil ? saved : [self addressFromMeCard];
}

+ (void)setAddress:(NSDictionary *)address
{
    [[NSUserDefaults standardUserDefaults] setObject:address forKey:CPAddressKey];
}

#pragma mark Filling

+ (void)fillFormInTab:(CPTab *)tab
{
    WebView *webView = [tab isDiscarded] ? nil : [tab webView];
    NSWindow *window = [webView window];
    NSString *host = CPHost(tab);
    NSArray *survey = CPFieldsOf(CPRunCommand(webView, @"survey", nil));
    NSArray *kinds = [survey count] ? [[survey objectAtIndex:0] componentsSeparatedByString:@","] : [NSArray array];
    NSString *typedUsername = [survey count] > 1 ? [survey objectAtIndex:1] : @"";
    BOOL hasUsernameField = [survey count] > 2 && [[survey objectAtIndex:2] isEqualToString:@"1"];
    BOOL hasPassword = [kinds containsObject:@"password"];
    NSArray *accounts = host != nil ? [CPKeychain accountsForHost:host] : [NSArray array];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];

    if (webView == nil)
        return;

    // A login: the password field, or the first step of one.
    if (hasPassword || (hasUsernameField && [accounts count] && ![kinds containsObject:@"postal-code"] && ![kinds containsObject:@"cc-number"])) {
        NSString *account;
        if (![accounts count]) {
            NSBeep();
            return;
        }
        account = [accounts containsObject:typedUsername] ? typedUsername
            : CPChoose(accounts, [NSString stringWithFormat:@"Which login for %@?", host], window);
        if (account == nil)
            return;
        [values setObject:account forKey:@"username"];
        if (hasPassword) {
            NSString *password;
            if (![self unlockWithPrompt:[NSString stringWithFormat:@"Captain Polliwog wants to fill in your password for %@.", host]])
                return;
            password = [CPKeychain passwordForHost:host account:account];
            if (password == nil) {
                NSBeep();
                return;
            }
            [values setObject:password forKey:@"password"];
            if (CPFilledLogins == nil)
                CPFilledLogins = [[NSMutableDictionary alloc] init];
            [CPFilledLogins setObject:[NSArray arrayWithObjects:account, password, nil] forKey:host];
        }
        CPRunCommand(webView, @"fill", values);
        return;
    }

    // A card, with the address around it.
    if ([kinds containsObject:@"cc-number"]) {
        NSArray *cards;
        NSMutableArray *labels = [NSMutableArray array];
        NSString *label;
        NSDictionary *card = nil;
        unsigned i;
        if (![self unlockWithPrompt:@"Captain Polliwog wants to fill in a saved card."])
            return;
        cards = [CPKeychain cards];
        for (i = 0; i < [cards count]; i++)
            [labels addObject:[[cards objectAtIndex:i] objectForKey:@"label"]];
        if (![labels count]) {
            NSBeep();
            return;
        }
        label = CPChoose(labels, @"Which card?", window);
        for (i = 0; label != nil && i < [cards count]; i++) {
            if ([[[cards objectAtIndex:i] objectForKey:@"label"] isEqualToString:label])
                card = [cards objectAtIndex:i];
        }
        if (card == nil)
            return;
        [values addEntriesFromDictionary:[self address]];
        [values setObject:[card objectForKey:@"number"] forKey:@"cc-number"];
        if ([card objectForKey:@"name"])
            [values setObject:[card objectForKey:@"name"] forKey:@"cc-name"];
        if ([card objectForKey:@"month"])
            [values setObject:[card objectForKey:@"month"] forKey:@"cc-exp-month"];
        if ([card objectForKey:@"year"])
            [values setObject:[card objectForKey:@"year"] forKey:@"cc-exp-year"];
        CPRunCommand(webView, @"fill", values);
        return;
    }

    // An address.
    if ([kinds count] && ![[kinds objectAtIndex:0] isEqualToString:@""]) {
        [values addEntriesFromDictionary:[self address]];
        if ([values count] && [CPRunCommand(webView, @"fill", values) intValue] > 0)
            return;
    }
    NSBeep();
}

#pragma mark Saving

+ (void)saveAlertDidEnd:(NSAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    NSArray *login = [(NSArray *)contextInfo autorelease];
    NSString *host = [login objectAtIndex:0], *account = [login objectAtIndex:1], *password = [login objectAtIndex:2];

    if (returnCode == NSAlertFirstButtonReturn) {
        if (![CPKeychain savePassword:password forHost:host account:account])
            NSBeep();
    } else if (returnCode == NSAlertThirdButtonReturn) {
        NSMutableArray *never = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:CPNeverSaveKey]];
        [never addObject:host];
        [[NSUserDefaults standardUserDefaults] setObject:never forKey:CPNeverSaveKey];
    }
}

+ (void)offerToSave:(NSArray *)login
{
    NSWindow *window = [login objectAtIndex:3];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    NSString *host = [login objectAtIndex:0], *account = [login objectAtIndex:1];
    BOOL known = [[CPKeychain accountsForHost:host] containsObject:account];

    [alert setMessageText:[NSString stringWithFormat:(known ? @"Update your saved password for %@?" : @"Save your password for %@?"), host]];
    [alert setInformativeText:[NSString stringWithFormat:
        @"For %@. Captain Polliwog keeps passwords in your Mac's Keychain, and fills them in only after you type your Mac's password.", account]];
    [alert addButtonWithTitle:(known ? @"Update" : @"Save")];
    [alert addButtonWithTitle:@"Not Now"];
    [alert addButtonWithTitle:@"Never for This Website"];
    if ([window attachedSheet] != nil) {
        [self saveAlertDidEnd:alert returnCode:[alert runModal] contextInfo:[[login subarrayWithRange:NSMakeRange(0, 3)] retain]];
        return;
    }
    [alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:@selector(saveAlertDidEnd:returnCode:contextInfo:)
                        contextInfo:[[login subarrayWithRange:NSMakeRange(0, 3)] retain]];
}

+ (void)captureLoginInTab:(CPTab *)tab
{
    WebView *webView = [tab isDiscarded] ? nil : [tab webView];
    NSString *host = CPHost(tab);
    NSArray *captured, *filled;
    NSString *password, *username;

    if (webView == nil || host == nil || [[CPPrivateBrowsing sharedPrivateBrowsing] isEnabled])
        return;
    captured = CPFieldsOf(CPRunCommand(webView, @"capture", nil));
    if ([captured count] < 2)
        return;
    password = [captured objectAtIndex:0];
    username = [captured objectAtIndex:1];

    if (CPTypedUsernames == nil)
        CPTypedUsernames = [[NSMutableDictionary alloc] init];
    if (![password length]) {
        // A first step: remember who is signing in.
        if ([username length])
            [CPTypedUsernames setObject:username forKey:host];
        return;
    }
    if (![username length])
        username = [CPTypedUsernames objectForKey:host];
    if (![username length])
        return;
    if ([[[NSUserDefaults standardUserDefaults] arrayForKey:CPNeverSaveKey] containsObject:host])
        return;
    filled = [CPFilledLogins objectForKey:host];
    if (filled != nil && [[filled objectAtIndex:0] isEqualToString:username] && [[filled objectAtIndex:1] isEqualToString:password])
        return;
    if ([webView window] == nil)
        return;
    {
        NSArray *offer = [NSArray arrayWithObjects:host, username, password, nil];
        if ([offer isEqualToArray:CPLastOffered] && CPLastOfferedAt != nil && [CPLastOfferedAt timeIntervalSinceNow] > -120.0)
            return;
        [CPLastOffered release];
        CPLastOffered = [offer retain];
        [CPLastOfferedAt release];
        CPLastOfferedAt = [[NSDate date] retain];
    }
    // After the page's navigation has started, not in the middle of it.
    [self performSelector:@selector(offerToSave:)
               withObject:[NSArray arrayWithObjects:host, username, password, [webView window], nil]
               afterDelay:0.5];
}

@end
