/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPAutoFillController.h"
#import "CPAutoFill.h"
#import "CPKeychain.h"
#import <AddressBook/AddressBook.h>
#import <AddressBook/AddressBookUI.h>

#define CPWindowWidth   520.0f
#define CPWindowHeight  420.0f

static NSTextField *CPAutoFillLabel(NSView *parent, NSRect frame, NSString *text, BOOL small, BOOL rightAligned)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    if (small) {
        [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [label setTextColor:[NSColor darkGrayColor]];
    }
    if (rightAligned)
        [label setAlignment:NSRightTextAlignment];
    [parent addSubview:label];
    [label release];
    return label;
}

static NSButton *CPAutoFillButton(NSView *parent, NSRect frame, NSString *title, id target, SEL action)
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [button setTarget:target];
    [button setAction:action];
    [parent addSubview:button];
    [button release];
    return button;
}

static NSTextField *CPAutoFillField(NSView *parent, NSRect frame)
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    [[field cell] setScrollable:YES];
    [parent addSubview:field];
    [field release];
    return field;
}

static NSTableView *CPAutoFillTable(NSView *parent, NSRect frame, NSArray *columns, id owner)
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    unsigned i;
    for (i = 0; i < [columns count]; i += 3) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[columns objectAtIndex:i]];
        [[column headerCell] setStringValue:[columns objectAtIndex:i + 1]];
        [column setWidth:[[columns objectAtIndex:i + 2] floatValue]];
        [column setEditable:NO];
        [table addTableColumn:column];
        [column release];
    }
    [table setDataSource:owner];
    [table setUsesAlternatingRowBackgroundColors:YES];
    [scroll setDocumentView:table];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    [parent addSubview:scroll];
    [table release];
    [scroll release];
    return table;
}

// The address fields, in the order shown.
static NSString *CPAddressKinds[] = {
    @"given-name", @"First name", @"family-name", @"Last name", @"email", @"Email", @"tel", @"Phone",
    @"address-line1", @"Street", @"address-line2", @"Apt, suite", @"address-level2", @"City",
    @"address-level1", @"State", @"postal-code", @"ZIP code", @"country", @"Country", nil
};

@interface CPAutoFillController (Private)
- (void)buildInterface;
- (void)showAddress:(NSDictionary *)address;
- (void)reloadLogins;
- (void)reloadCards;
@end

@implementation CPAutoFillController (Private)

- (void)buildInterface
{
    NSView *content = [[self window] contentView];
    NSTabViewItem *item;
    NSView *view;
    float top;
    unsigned i;

    tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(12.0f, 12.0f, CPWindowWidth - 24.0f, CPWindowHeight - 24.0f)];
    [tabs setDelegate:self];
    [content addSubview:tabs];
    [tabs release];

    // Passwords
    item = [[[NSTabViewItem alloc] initWithIdentifier:@"passwords"] autorelease];
    [item setLabel:@"Passwords"];
    view = [item view];
    loginTable = CPAutoFillTable(view, NSMakeRect(12.0f, 52.0f, 460.0f, 280.0f),
        [NSArray arrayWithObjects:@"host", @"Website", [NSNumber numberWithFloat:230.0f], @"account", @"Username", [NSNumber numberWithFloat:210.0f], nil], self);
    CPAutoFillButton(view, NSMakeRect(8.0f, 16.0f, 90.0f, 24.0f), @"Remove", self, @selector(removeLogin:));
    CPAutoFillLabel(view, NSMakeRect(104.0f, 14.0f, 370.0f, 28.0f),
        @"Passwords Safari saved are here too: both keep them in your Mac's Keychain.", YES, NO);
    [tabs addTabViewItem:item];

    // Address
    item = [[[NSTabViewItem alloc] initWithIdentifier:@"address"] autorelease];
    [item setLabel:@"Address"];
    view = [item view];
    addressFields = [[NSMutableDictionary alloc] init];
    top = 300.0f;
    for (i = 0; CPAddressKinds[i] != nil; i += 2) {
        CPAutoFillLabel(view, NSMakeRect(12.0f, top + 2.0f, 90.0f, 17.0f), CPAddressKinds[i + 1], NO, YES);
        [addressFields setObject:CPAutoFillField(view, NSMakeRect(108.0f, top, 300.0f, 22.0f)) forKey:CPAddressKinds[i]];
        top -= 28.0f;
    }
    CPAutoFillButton(view, NSMakeRect(12.0f, 12.0f, 86.0f, 24.0f), @"My Card", self, @selector(useMeCard:));
    CPAutoFillButton(view, NSMakeRect(104.0f, 12.0f, 110.0f, 24.0f), @"Contacts...", self, @selector(chooseContact:));
    CPAutoFillButton(view, NSMakeRect(218.0f, 12.0f, 90.0f, 24.0f), @"Save", self, @selector(saveAddress:));
    [tabs addTabViewItem:item];

    // Cards
    item = [[[NSTabViewItem alloc] initWithIdentifier:@"cards"] autorelease];
    [item setLabel:@"Cards"];
    view = [item view];
    cardTable = CPAutoFillTable(view, NSMakeRect(12.0f, 130.0f, 460.0f, 200.0f),
        [NSArray arrayWithObjects:@"name", @"Name on card", [NSNumber numberWithFloat:180.0f], @"number", @"Number", [NSNumber numberWithFloat:160.0f],
         @"expires", @"Expires", [NSNumber numberWithFloat:90.0f], nil], self);
    CPAutoFillButton(view, NSMakeRect(8.0f, 96.0f, 90.0f, 24.0f), @"Remove", self, @selector(removeCard:));
    CPAutoFillLabel(view, NSMakeRect(12.0f, 70.0f, 90.0f, 17.0f), @"Name on card", NO, YES);
    cardName = CPAutoFillField(view, NSMakeRect(108.0f, 68.0f, 200.0f, 22.0f));
    CPAutoFillLabel(view, NSMakeRect(12.0f, 42.0f, 90.0f, 17.0f), @"Number", NO, YES);
    cardNumber = CPAutoFillField(view, NSMakeRect(108.0f, 40.0f, 200.0f, 22.0f));
    CPAutoFillLabel(view, NSMakeRect(310.0f, 42.0f, 50.0f, 17.0f), @"Expires", NO, YES);
    cardMonth = CPAutoFillField(view, NSMakeRect(364.0f, 40.0f, 32.0f, 22.0f));
    CPAutoFillLabel(view, NSMakeRect(398.0f, 42.0f, 10.0f, 17.0f), @"/", NO, NO);
    cardYear = CPAutoFillField(view, NSMakeRect(410.0f, 40.0f, 52.0f, 22.0f));
    CPAutoFillButton(view, NSMakeRect(104.0f, 8.0f, 100.0f, 24.0f), @"Add Card", self, @selector(addCard:));
    CPAutoFillLabel(view, NSMakeRect(210.0f, 4.0f, 262.0f, 30.0f),
        @"Security codes are never kept: type the code each time you pay.", YES, NO);
    [tabs addTabViewItem:item];
}

- (void)showAddress:(NSDictionary *)address
{
    NSEnumerator *kinds = [addressFields keyEnumerator];
    NSString *kind;
    while ((kind = [kinds nextObject]) != nil) {
        NSString *value = [address objectForKey:kind];
        [[addressFields objectForKey:kind] setStringValue:(value != nil ? value : @"")];
    }
}

- (void)reloadLogins
{
    [logins release];
    logins = [[CPKeychain allLogins] retain];
    [loginTable reloadData];
}

- (void)reloadCards
{
    [cards release];
    cards = cardsUnlocked ? [[CPKeychain cards] retain] : nil;
    [cardTable reloadData];
}

@end

@implementation CPAutoFillController

+ (CPAutoFillController *)sharedController
{
    static CPAutoFillController *controller = nil;
    if (controller == nil)
        controller = [[CPAutoFillController alloc] init];
    return controller;
}

- (id)init
{
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f, 0.0f, CPWindowWidth, CPWindowHeight)
                                                    styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                      backing:NSBackingStoreBuffered
                                                        defer:YES] autorelease];
    self = [super initWithWindow:window];
    if (self == nil)
        return nil;
    [window setTitle:@"AutoFill"];
    [window setDelegate:self];
    [window center];
    [self buildInterface];
    return self;
}

- (void)dealloc
{
    [logins release];
    [cards release];
    [addressFields release];
    [super dealloc];
}

- (void)showWindow:(id)sender
{
    [self reloadLogins];
    [self showAddress:[CPAutoFill address]];
    [self reloadCards];
    [super showWindow:sender];
}

- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)item
{
    // Cards show only after the Mac's password, as they fill only after it.
    if ([[item identifier] isEqual:@"cards"] && !cardsUnlocked) {
        if (![CPAutoFill unlockWithPrompt:@"Captain Polliwog wants to show your saved cards."])
            return NO;
        cardsUnlocked = YES;
        [self reloadCards];
    }
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification
{
    cardsUnlocked = NO;
    [cards release];
    cards = nil;
}

#pragma mark Actions

- (IBAction)removeLogin:(id)sender
{
    int row = [loginTable selectedRow];
    NSDictionary *login;
    if (row < 0 || (unsigned)row >= [logins count])
        return;
    login = [logins objectAtIndex:row];
    if (![CPAutoFill unlockWithPrompt:@"Captain Polliwog wants to remove a saved password."])
        return;
    [CPKeychain removeLoginForHost:[login objectForKey:@"host"] account:[login objectForKey:@"account"]];
    [self reloadLogins];
}

- (IBAction)useMeCard:(id)sender
{
    [self showAddress:[CPAutoFill addressFromMeCard]];
}

// Anyone in the Address Book, not only the card marked as you. The picker is
// Address Book's own view, so the list looks and searches as it does there.
- (IBAction)chooseContact:(id)sender
{
    if (contactsPanel == nil) {
        NSRect frame = NSMakeRect(0.0f, 0.0f, 440.0f, 340.0f);
        NSView *content;

        contactsPanel = [[NSPanel alloc] initWithContentRect:frame
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
        [contactsPanel setTitle:@"Contacts"];
        content = [contactsPanel contentView];

        peoplePicker = [[ABPeoplePickerView alloc] initWithFrame:
            NSMakeRect(12.0f, 52.0f, NSWidth(frame) - 24.0f, NSHeight(frame) - 64.0f)];
        [peoplePicker setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
        [peoplePicker setAllowsMultipleSelection:NO];
        [peoplePicker setAllowsGroupSelection:NO];
        [content addSubview:peoplePicker];
        [peoplePicker release];

        CPAutoFillButton(content, NSMakeRect(NSWidth(frame) - 100.0f, 12.0f, 88.0f, 24.0f),
                         @"Use Contact", self, @selector(useChosenContact:));
        CPAutoFillButton(content, NSMakeRect(NSWidth(frame) - 194.0f, 12.0f, 88.0f, 24.0f),
                         @"Cancel", self, @selector(cancelChooseContact:));
        [contactsPanel center];
    }
    [contactsPanel makeKeyAndOrderFront:sender];
}

- (IBAction)useChosenContact:(id)sender
{
    NSArray *chosen = [peoplePicker selectedRecords];

    if ([chosen count] > 0) {
        id person = [chosen objectAtIndex:0];
        if ([person isKindOfClass:[ABPerson class]])
            [self showAddress:[CPAutoFill addressFromPerson:person]];
    }
    [contactsPanel orderOut:sender];
}

- (IBAction)cancelChooseContact:(id)sender
{
    [contactsPanel orderOut:sender];
}

- (IBAction)saveAddress:(id)sender
{
    NSMutableDictionary *address = [NSMutableDictionary dictionary];
    NSEnumerator *kinds = [addressFields keyEnumerator];
    NSString *kind;
    while ((kind = [kinds nextObject]) != nil) {
        NSString *value = [[[addressFields objectForKey:kind] stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([value length])
            [address setObject:value forKey:kind];
    }
    [CPAutoFill setAddress:address];
}

- (IBAction)addCard:(id)sender
{
    NSMutableString *digits = [NSMutableString string];
    NSString *number = [cardNumber stringValue];
    unsigned i;
    NSDictionary *card;

    for (i = 0; i < [number length]; i++) {
        unichar c = [number characterAtIndex:i];
        if (c >= '0' && c <= '9')
            [digits appendFormat:@"%C", c];
    }
    if ([digits length] < 12 || [[cardMonth stringValue] intValue] < 1 || [[cardMonth stringValue] intValue] > 12
        || [[cardYear stringValue] intValue] < 1) {
        NSBeep();
        return;
    }
    if (!cardsUnlocked && ![CPAutoFill unlockWithPrompt:@"Captain Polliwog wants to save a card."])
        return;
    cardsUnlocked = YES;
    card = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithFormat:@"%@ ending %@", ([[cardName stringValue] length] ? [cardName stringValue] : @"Card"),
             [digits substringFromIndex:[digits length] - 4]], @"label",
            [cardName stringValue], @"name",
            digits, @"number",
            [NSString stringWithFormat:@"%02d", [[cardMonth stringValue] intValue]], @"month",
            [NSString stringWithFormat:@"%d", ([[cardYear stringValue] intValue] < 100 ? 2000 : 0) + [[cardYear stringValue] intValue]], @"year",
            nil];
    [CPKeychain saveCard:card];
    [cardName setStringValue:@""];
    [cardNumber setStringValue:@""];
    [cardMonth setStringValue:@""];
    [cardYear setStringValue:@""];
    [self reloadCards];
}

- (IBAction)removeCard:(id)sender
{
    int row = [cardTable selectedRow];
    if (row < 0 || (unsigned)row >= [cards count])
        return;
    [CPKeychain removeCardWithLabel:[[cards objectAtIndex:row] objectForKey:@"label"]];
    [self reloadCards];
}

#pragma mark Tables

- (int)numberOfRowsInTableView:(NSTableView *)table
{
    return table == loginTable ? [logins count] : [cards count];
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(int)row
{
    NSString *identifier = [column identifier];
    if (table == loginTable)
        return [[logins objectAtIndex:row] objectForKey:identifier];
    {
        NSDictionary *card = [cards objectAtIndex:row];
        NSString *number = [card objectForKey:@"number"];
        if ([identifier isEqualToString:@"number"])
            return [number length] > 4 ? [NSString stringWithFormat:@"%C%C%C%C %@", 0x2022, 0x2022, 0x2022, 0x2022, [number substringFromIndex:[number length] - 4]] : @"";
        if ([identifier isEqualToString:@"expires"])
            return [NSString stringWithFormat:@"%@/%@", [card objectForKey:@"month"], [card objectForKey:@"year"]];
        return [card objectForKey:identifier];
    }
}

@end
