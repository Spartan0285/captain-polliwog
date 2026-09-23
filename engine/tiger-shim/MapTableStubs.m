/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// NSMapTable, which arrived in Leopard. Tiger has the same table as C
// functions (NSCreateMapTable) and no class.
//
// This one keeps its entries in a dictionary, keyed on the address of the
// key object rather than its -hash, which is what a map table does. The
// weak options are honoured as strong: an entry outlives what it points at
// rather than vanishing. WebKit uses these as caches, which is the safe
// direction to err in.
//
// Only the headers that do not declare NSMapTable are imported, since the
// 10.5 SDK we build against declares it and this file defines it.

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSValue.h>

enum {
    CPMapTableStrongMemory = 0,
    CPMapTableZeroingWeakMemory = 1 << 0,
    CPMapTableCopyIn = 1 << 1,
    CPMapTableObjectPointerPersonality = 1 << 2
};

@interface NSMapTable : NSObject
{
    NSMutableDictionary *entries;
    NSMutableArray      *keys;      // pointer keys are not copied, so kept here
    BOOL                 copiesKeys;
}
+ (id)mapTableWithKeyOptions:(NSUInteger)keyOptions valueOptions:(NSUInteger)valueOptions;
+ (id)strongToStrongObjectsMapTable;
+ (id)strongToWeakObjectsMapTable;
+ (id)weakToStrongObjectsMapTable;
+ (id)weakToWeakObjectsMapTable;
- (id)initWithKeyOptions:(NSUInteger)keyOptions valueOptions:(NSUInteger)valueOptions capacity:(NSUInteger)capacity;
- (id)objectForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key;
- (void)removeObjectForKey:(id)key;
- (void)removeAllObjects;
- (NSUInteger)count;
- (NSEnumerator *)keyEnumerator;
- (NSEnumerator *)objectEnumerator;
- (NSDictionary *)dictionaryRepresentation;
@end

// Pointer identity, not -isEqual:, is what a map table keys on. Wrapping the
// address in a number gives that without retaining the key.
static id CPMapKey(id key)
{
    return [NSNumber numberWithUnsignedLong:(unsigned long)key];
}

@implementation NSMapTable

- (id)initWithKeyOptions:(NSUInteger)keyOptions valueOptions:(NSUInteger)valueOptions capacity:(NSUInteger)capacity
{
    self = [super init];
    if (self == nil)
        return nil;
    entries = [[NSMutableDictionary alloc] initWithCapacity:capacity];
    keys = [[NSMutableArray alloc] init];
    copiesKeys = (keyOptions & CPMapTableCopyIn) != 0;
    return self;
}

- (id)init
{
    return [self initWithKeyOptions:0 valueOptions:0 capacity:0];
}

- (void)dealloc
{
    [entries release];
    [keys release];
    [super dealloc];
}

+ (id)mapTableWithKeyOptions:(NSUInteger)keyOptions valueOptions:(NSUInteger)valueOptions
{
    return [[[self alloc] initWithKeyOptions:keyOptions valueOptions:valueOptions capacity:0] autorelease];
}

+ (id)strongToStrongObjectsMapTable { return [self mapTableWithKeyOptions:0 valueOptions:0]; }
+ (id)strongToWeakObjectsMapTable   { return [self mapTableWithKeyOptions:0 valueOptions:0]; }
+ (id)weakToStrongObjectsMapTable   { return [self mapTableWithKeyOptions:0 valueOptions:0]; }
+ (id)weakToWeakObjectsMapTable     { return [self mapTableWithKeyOptions:0 valueOptions:0]; }

- (id)objectForKey:(id)key
{
    return key != nil ? [entries objectForKey:CPMapKey(key)] : nil;
}

- (void)setObject:(id)object forKey:(id)key
{
    if (key == nil)
        return;
    if (object == nil) {
        [self removeObjectForKey:key];
        return;
    }
    if ([entries objectForKey:CPMapKey(key)] == nil)
        [keys addObject:[NSValue valueWithPointer:key]];
    [entries setObject:object forKey:CPMapKey(key)];
}

- (void)removeObjectForKey:(id)key
{
    if (key == nil)
        return;
    [entries removeObjectForKey:CPMapKey(key)];
    {
        NSValue *pointer = [NSValue valueWithPointer:key];
        NSUInteger index = [keys indexOfObject:pointer];
        if (index != NSNotFound)
            [keys removeObjectAtIndex:index];
    }
}

- (void)removeAllObjects
{
    [entries removeAllObjects];
    [keys removeAllObjects];
}

- (NSUInteger)count
{
    return [entries count];
}

- (NSEnumerator *)keyEnumerator
{
    NSMutableArray *live = [NSMutableArray arrayWithCapacity:[keys count]];
    NSEnumerator *stored = [keys objectEnumerator];
    NSValue *pointer;
    while ((pointer = [stored nextObject]) != nil) {
        id key = (id)[pointer pointerValue];
        if ([entries objectForKey:CPMapKey(key)] != nil)
            [live addObject:key];
    }
    return [live objectEnumerator];
}

- (NSEnumerator *)objectEnumerator
{
    return [[entries allValues] objectEnumerator];
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSEnumerator *live = [self keyEnumerator];
    id key;
    while ((key = [live nextObject]) != nil) {
        id object = [self objectForKey:key];
        if (object != nil && [key conformsToProtocol:@protocol(NSCopying)])
            [result setObject:object forKey:key];
    }
    return result;
}

@end

