/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// CFError, the private CFNetwork calls, and the CommonCrypto additions.
//
// CFError is Leopard's, and is a small thing: a domain, a code and a
// dictionary. It is implemented here rather than stubbed, because errors do
// happen and the engine reads them.
//
// The CFNetwork half is different. Captain Polliwog does all of its own
// networking through libcurl - cookies, cache, proxies and credentials
// included - so WebKit's private CFNetwork path is never the one in use on
// this browser. These answer as an empty store answers: no cookies, no
// cached response, no proxy, no credential. If something ever does come
// through here it will behave as though the store were empty rather than
// stopping the browser, and the log line says so once.

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

static void CPUnsupported(const char *what)
{
    static int said[64];
    static int count;
    int i;
    for (i = 0; i < count && i < 64; i++)
        if (said[i] == (int)(intptr_t)what)
            return;
    if (count < 64)
        said[count++] = (int)(intptr_t)what;
    fprintf(stderr, "Captain Polliwog: %s is not on this system; answering as empty\n", what);
}

#pragma mark CFError

// A CFError is a CFDictionary here, holding domain, code and user info: the
// engine only ever reads those three back out.
static CFStringRef CPErrorDomainKey = CFSTR("CPErrorDomain");
static CFStringRef CPErrorCodeKey = CFSTR("CPErrorCode");
static CFStringRef CPErrorUserInfoKey = CFSTR("CPErrorUserInfo");

const CFStringRef kCFErrorDomainOSStatus = CFSTR("NSOSStatusErrorDomain");
const CFStringRef kCFErrorDomainMach = CFSTR("NSMachErrorDomain");
const CFStringRef kCFErrorDomainPOSIX = CFSTR("NSPOSIXErrorDomain");
const CFStringRef kCFErrorLocalizedDescriptionKey = CFSTR("NSLocalizedDescription");

CFErrorRef CFErrorCreate(CFAllocatorRef allocator, CFStringRef domain, CFIndex code, CFDictionaryRef userInfo)
{
    CFMutableDictionaryRef error = CFDictionaryCreateMutable(allocator, 3,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFNumberRef number = CFNumberCreate(allocator, kCFNumberCFIndexType, &code);

    if (domain != NULL)
        CFDictionarySetValue(error, CPErrorDomainKey, domain);
    CFDictionarySetValue(error, CPErrorCodeKey, number);
    if (userInfo != NULL)
        CFDictionarySetValue(error, CPErrorUserInfoKey, userInfo);
    CFRelease(number);
    return (CFErrorRef)error;
}

CFStringRef CFErrorGetDomain(CFErrorRef error)
{
    return error != NULL ? (CFStringRef)CFDictionaryGetValue((CFDictionaryRef)error, CPErrorDomainKey) : NULL;
}

CFIndex CFErrorGetCode(CFErrorRef error)
{
    CFNumberRef number = error != NULL
        ? (CFNumberRef)CFDictionaryGetValue((CFDictionaryRef)error, CPErrorCodeKey) : NULL;
    CFIndex code = 0;
    if (number != NULL)
        CFNumberGetValue(number, kCFNumberCFIndexType, &code);
    return code;
}

CFDictionaryRef CFErrorCopyUserInfo(CFErrorRef error)
{
    CFDictionaryRef info = error != NULL
        ? (CFDictionaryRef)CFDictionaryGetValue((CFDictionaryRef)error, CPErrorUserInfoKey) : NULL;
    return info != NULL ? (CFDictionaryRef)CFRetain(info) : NULL;
}

CFStringRef CFErrorCopyDescription(CFErrorRef error)
{
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@ %ld"),
                                    CFErrorGetDomain(error), (long)CFErrorGetCode(error));
}

CFErrorRef CFReadStreamCopyError(CFReadStreamRef stream)
{
    CFStreamError error = CFReadStreamGetError(stream);
    return CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, error.error, NULL);
}

CFErrorRef CFWriteStreamCopyError(CFWriteStreamRef stream)
{
    CFStreamError error = CFWriteStreamGetError(stream);
    return CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, error.error, NULL);
}

#pragma mark Locale and strings

// Tiger keeps the same list under the same preference.
CFArrayRef CFLocaleCopyPreferredLanguages(void)
{
    CFArrayRef languages = (CFArrayRef)CFPreferencesCopyAppValue(CFSTR("AppleLanguages"),
                                                                 kCFPreferencesCurrentApplication);
    if (languages != NULL && CFGetTypeID(languages) == CFArrayGetTypeID())
        return languages;
    if (languages != NULL)
        CFRelease(languages);
    {
        CFStringRef english = CFSTR("en");
        return CFArrayCreate(kCFAllocatorDefault, (const void **)&english, 1, &kCFTypeArrayCallBacks);
    }
}

Boolean CFLocaleGetLanguageRegionEncodingForLocaleIdentifier(CFStringRef identifier, LangCode *language,
                                                             RegionCode *region, ScriptCode *script,
                                                             CFStringEncoding *encoding)
{
    return false;       // "not known", which the caller falls back from
}

// The locale argument orders case-insensitive matching for a few languages;
// without it the search is the same search, ordered by Unicode.
Boolean CFStringFindWithOptionsAndLocale(CFStringRef string, CFStringRef toFind,
                                         CFRange range, CFStringCompareFlags options,
                                         CFLocaleRef locale, CFRange *result)
{
    return CFStringFindWithOptions(string, toFind, range, options, result);
}

const CFStringRef kCFLocaleCurrentLocaleDidChangeNotification = CFSTR("kCFLocaleCurrentLocaleDidChangeNotification");

#pragma mark CFNetwork, which this browser does not use

const CFStringRef kCFHTTPAuthenticationSchemeNTLM = CFSTR("NTLM");
const CFStringRef kCFHTTPAuthenticationSchemeNegotiate = CFSTR("Negotiate");
const CFStringRef kCFStreamPropertySSLPeerTrust = CFSTR("kCFStreamPropertySSLPeerTrust");
const CFStringRef kCFProxyTypeKey = CFSTR("kCFProxyTypeKey");
const CFStringRef kCFProxyHostNameKey = CFSTR("kCFProxyHostNameKey");
const CFStringRef kCFProxyPortNumberKey = CFSTR("kCFProxyPortNumberKey");
const CFStringRef kCFProxyAutoConfigurationURLKey = CFSTR("kCFProxyAutoConfigurationURLKey");
const CFStringRef kCFProxyTypeNone = CFSTR("kCFProxyTypeNone");
const CFStringRef kCFProxyTypeHTTP = CFSTR("kCFProxyTypeHTTP");
const CFStringRef kCFProxyTypeHTTPS = CFSTR("kCFProxyTypeHTTPS");
const CFStringRef kCFProxyTypeSOCKS = CFSTR("kCFProxyTypeSOCKS");
const CFStringRef kCFProxyTypeAutoConfigurationURL = CFSTR("kCFProxyTypeAutoConfigurationURL");

#define CP_EMPTY_OBJECT(name, type)  type name() { CPUnsupported(#name); return NULL; }

CFTypeRef _CFHTTPCookieStorageGetDefault(CFAllocatorRef allocator)
{
    CPUnsupported("the system cookie store");
    return NULL;
}

CFArrayRef CFHTTPCookieStorageCopyCookiesForURL(CFTypeRef storage, CFURLRef url, Boolean sendSecure)
{
    return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
}

void CFHTTPCookieStorageSetCookies(CFTypeRef storage, CFArrayRef cookies, CFURLRef url, CFURLRef mainURL) { }
void CFHTTPCookieStorageDeleteCookie(CFTypeRef storage, CFTypeRef cookie) { }
void CFHTTPCookieStorageAddObserver(CFTypeRef storage, CFRunLoopRef runLoop, CFStringRef mode, void *callback, void *info) { }
void CFHTTPCookieStorageRemoveObserver(CFTypeRef storage, CFRunLoopRef runLoop, CFStringRef mode, void *callback, void *info) { }
void CFHTTPCookieStorageScheduleWithRunLoop(CFTypeRef storage, CFRunLoopRef runLoop, CFStringRef mode) { }
void CFHTTPCookieStorageSetCookieAcceptPolicy(CFTypeRef storage, CFIndex policy) { }
CFIndex CFHTTPCookieStorageGetCookieAcceptPolicy(CFTypeRef storage) { return 0; }

CFArrayRef CFNetworkCopyProxiesForURL(CFURLRef url, CFDictionaryRef proxySettings)
{
    CFDictionaryRef none = CFDictionaryCreate(kCFAllocatorDefault,
        (const void **)&kCFProxyTypeKey, (const void **)&kCFProxyTypeNone, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef proxies = CFArrayCreate(kCFAllocatorDefault, (const void **)&none, 1, &kCFTypeArrayCallBacks);
    CFRelease(none);
    return proxies;
}

CFTypeRef CFNetworkExecuteProxyAutoConfigurationURL(CFURLRef scriptURL, CFURLRef targetURL,
                                                    void *callback, void *context)
{
    CPUnsupported("proxy auto-configuration");
    return NULL;
}

// The URL cache and credential store: the browser keeps its own of each.
CFTypeRef CFURLCacheCopyResponseForRequest(CFTypeRef cache, CFTypeRef request) { return NULL; }
CFTypeRef _CFURLCacheCopyCacheDirectory(CFTypeRef cache) { return NULL; }
void CFURLCacheSetMemoryCapacity(CFTypeRef cache, CFIndex capacity) { }
void CFURLCacheSetDiskCapacity(CFTypeRef cache, CFIndex capacity) { }
CFTypeRef CFURLCredentialStorageCreate(CFAllocatorRef allocator) { return NULL; }
CFTypeRef CFURLCredentialStorageCopyDefaultCredentialForProtectionSpace(CFTypeRef storage, CFTypeRef space) { return NULL; }

// The request and response accessors WebKit uses when CFNetwork is the
// loader. Ours is NSURLProtocol, so nothing reaches these.
CFTypeRef CFURLRequestCreateMutableCopy(CFAllocatorRef allocator, CFTypeRef request) { return NULL; }
void CFURLRequestSetHTTPRequestBody(CFTypeRef request, CFDataRef body) { }
void CFURLRequestSetHTTPRequestBodyStream(CFTypeRef request, CFReadStreamRef stream) { }
void CFURLRequestSetHTTPRequestBodyParts(CFTypeRef request, CFArrayRef parts) { }
CFArrayRef CFURLRequestCopyHTTPRequestBodyParts(CFTypeRef request) { return NULL; }
void _CFURLRequestSetProtocolProperty(CFTypeRef request, CFStringRef key, CFTypeRef value) { }

CFTypeRef CFURLResponseCreateWithHTTPResponse(CFAllocatorRef allocator, CFURLRef url,
                                              CFTypeRef message, CFIndex policy) { return NULL; }
CFTypeRef CFURLResponseGetHTTPResponse(CFTypeRef response) { return NULL; }
CFURLRef CFURLResponseGetURL(CFTypeRef response) { return NULL; }
CFStringRef CFURLResponseGetMIMEType(CFTypeRef response) { return NULL; }
void CFURLResponseSetMIMEType(CFTypeRef response, CFStringRef type) { }
CFStringRef CFURLResponseCopySuggestedFilename(CFTypeRef response) { return NULL; }
CFTypeRef _CFURLResponseGetSSLCertificateContext(CFTypeRef response) { return NULL; }
