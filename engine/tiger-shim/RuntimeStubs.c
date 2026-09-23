/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// The Objective-C 2.0 runtime functions, over Tiger's Objective-C 1.
//
// Tiger has all the same machinery; 2.0 renamed it and hid the structures.
// Everything here walks the structures Tiger's runtime still uses, which are
// declared below rather than included, because the 10.5 SDK we build against
// no longer describes them.
//
// Also here: the handful of C library functions Leopard added, and the
// $UNIX2003 spellings a Leopard-built library asks for, which on Tiger are
// simply the functions themselves.

#include <objc/objc.h>
#include <objc/objc-runtime.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <fcntl.h>

#pragma mark The Objective-C 1 structures

// The 10.5 SDK still declares these, marked OBJC2_UNAVAILABLE - which means
// "not in the 64-bit runtime", and this is the 32-bit one. Tiger's runtime
// is exactly what they describe.

#define CP_CLASS_INFO_CLASS  0x1
#define CP_CLASS_INFO_META   0x2

#pragma mark Methods

// Every one of these takes nil, as the real runtime does. It matters:
// WebKit patches private AppKit methods that Tiger has not got, and
// class_getInstanceMethod answers nil for those. Apple's runtime shrugs;
// so does this one.

SEL method_getName(Method method)
{
    return method != NULL ? ((struct objc_method *)method)->method_name : NULL;
}

IMP method_getImplementation(Method method)
{
    return method != NULL ? ((struct objc_method *)method)->method_imp : NULL;
}

const char *method_getTypeEncoding(Method method)
{
    return method != NULL ? ((struct objc_method *)method)->method_types : NULL;
}

IMP method_setImplementation(Method method, IMP implementation)
{
    struct objc_method *m = (struct objc_method *)method;
    IMP was;

    if (m == NULL)
        return NULL;
    was = m->method_imp;
    m->method_imp = implementation;
    _objc_flush_caches(NULL);
    return was;
}

void method_exchangeImplementations(Method a, Method b)
{
    struct objc_method *first = (struct objc_method *)a, *second = (struct objc_method *)b;
    IMP swap;

    if (first == NULL || second == NULL)
        return;
    swap = first->method_imp;
    first->method_imp = second->method_imp;
    second->method_imp = swap;
    _objc_flush_caches(NULL);
}

BOOL class_addMethod(Class cls, SEL name, IMP implementation, const char *types)
{
    struct objc_method_list *list;

    if (cls == NULL || name == NULL || implementation == NULL)
        return NO;
    if (class_getInstanceMethod(cls, name) != NULL)
        return NO;      // 2.0 refuses to replace; method_setImplementation does that

    list = (struct objc_method_list *)calloc(1, sizeof(struct objc_method_list));
    list->method_count = 1;
    list->method_list[0].method_name = name;
    list->method_list[0].method_types = strdup(types != NULL ? types : "");
    list->method_list[0].method_imp = implementation;
    class_addMethods(cls, list);    // the runtime keeps the list; it is not freed
    return YES;
}

Method *class_copyMethodList(Class cls, unsigned int *outCount)
{
    struct objc_class *c = (struct objc_class *)cls;
    struct objc_method_list *list;
    void *iterator = NULL;
    unsigned int count = 0, index = 0;
    Method *methods;

    if (outCount != NULL)
        *outCount = 0;
    if (c == NULL)
        return NULL;

    while ((list = class_nextMethodList(cls, &iterator)) != NULL)
        count += list->method_count;
    if (count == 0)
        return NULL;

    methods = (Method *)calloc(count + 1, sizeof(Method));
    iterator = NULL;
    while ((list = class_nextMethodList(cls, &iterator)) != NULL) {
        int i;
        for (i = 0; i < list->method_count && index < count; i++)
            methods[index++] = (Method)&list->method_list[i];
    }
    if (outCount != NULL)
        *outCount = index;
    return methods;
}

#pragma mark Ivars

const char *ivar_getName(Ivar ivar)
{
    return ivar != NULL ? ((struct objc_ivar *)ivar)->ivar_name : NULL;
}

Ivar *class_copyIvarList(Class cls, unsigned int *outCount)
{
    struct objc_class *c = (struct objc_class *)cls;
    Ivar *ivars;
    int i, count;

    if (outCount != NULL)
        *outCount = 0;
    if (c == NULL || c->ivars == NULL || c->ivars->ivar_count == 0)
        return NULL;

    count = c->ivars->ivar_count;
    ivars = (Ivar *)calloc(count + 1, sizeof(Ivar));
    for (i = 0; i < count; i++)
        ivars[i] = (Ivar)&c->ivars->ivar_list[i];
    if (outCount != NULL)
        *outCount = (unsigned int)count;
    return ivars;
}

#pragma mark Classes

Class class_getSuperclass(Class cls)
{
    return cls != NULL ? (Class)((struct objc_class *)cls)->super_class : NULL;
}

Class object_getClass(id object)
{
    return object != NULL ? (Class)((struct objc_class *)object)->isa : NULL;
}

// A class and its metaclass, built by hand, as everyone did before 2.0.
Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes)
{
    struct objc_class *super = (struct objc_class *)superclass;
    struct objc_class *cls, *meta;

    if (name == NULL || objc_lookUpClass(name) != NULL)
        return NULL;
    if (super == NULL)
        return NULL;    // root classes are not made this way here

    cls = (struct objc_class *)calloc(1, sizeof(struct objc_class));
    meta = (struct objc_class *)calloc(1, sizeof(struct objc_class));

    meta->isa = super->isa->isa;
    meta->super_class = super->isa;
    meta->name = strdup(name);
    meta->info = CP_CLASS_INFO_META;
    meta->instance_size = super->isa->instance_size;

    cls->isa = meta;
    cls->super_class = super;
    cls->name = meta->name;
    cls->info = CP_CLASS_INFO_CLASS;
    cls->instance_size = super->instance_size + (long)extraBytes;
    return (Class)cls;
}

void objc_registerClassPair(Class cls)
{
    if (cls != NULL)
        objc_addClass(cls);
}

#pragma mark Odds and ends

// Garbage collection arrived with Leopard; Tiger never collects.
BOOL objc_collectingEnabled(void) { return NO; }
BOOL objc_finalizeOnMainThread(Class cls) { return NO; }

// Atomic property accessors copy structures through this.
void objc_copyStruct(void *destination, const void *source, ptrdiff_t size, BOOL atomic, BOOL strong)
{
    memcpy(destination, source, (size_t)size);
}

#pragma mark C library

// execinfo arrived in Leopard. Nothing here needs a real stack trace: it is
// used for logging a leak or an assertion, which says "0 frames" instead.
int backtrace(void **array, int size) { return 0; }
char **backtrace_symbols(void *const *array, int size) { return NULL; }

double log2(double x) { return log(x) / M_LN2; }
float modff(float value, float *integerPart)
{
    double whole = 0.0;
    double fraction = modf((double)value, &whole);
    *integerPart = (float)whole;
    return (float)fraction;
}
float nextafterf(float from, float to) { return (float)nextafter((double)from, (double)to); }

// Purgeable memory is Leopard's; on Tiger nothing is purgeable, which is
// what "not supported" means to the caller.
int mach_vm_purgable_control(unsigned int task, unsigned long long address, int control, int *state)
{
    if (state != NULL)
        *state = 0;
    return -1;
}

// The UNIX2003-conforming spellings a Leopard-built library asks for. On
// Tiger these are the plain functions.
int cp_close_unix2003(int fd) { return close(fd); }
ssize_t cp_read_unix2003(int fd, void *buffer, size_t length) { return read(fd, buffer, length); }
int cp_open_unix2003(const char *path, int flags, int mode) { return open(path, flags, mode); }

__asm__(".globl _close$UNIX2003\n_close$UNIX2003 = _cp_close_unix2003");
__asm__(".globl _read$UNIX2003\n_read$UNIX2003 = _cp_read_unix2003");
__asm__(".globl _open$UNIX2003\n_open$UNIX2003 = _cp_open_unix2003");
