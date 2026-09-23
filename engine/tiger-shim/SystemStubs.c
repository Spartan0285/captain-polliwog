/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

// The last few: CommonCrypto's block ciphers and SHA-224, which arrived in
// Leopard, and a handful of system calls that are each one line.
//
// SHA-224 is real (it is SHA-256 with different starting values and a
// shorter answer, and the engine hashes with it). The cipher interface is
// not: nothing in a browser without WebCrypto encrypts through it, and it
// reports failure rather than pretending to encrypt, which is the one
// answer that cannot quietly produce wrong data.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <CommonCrypto/CommonDigest.h>

#pragma mark SHA-224

// SHA-224 is SHA-256 with its own initial state, truncated to 28 bytes.
int CC_SHA224_Init(CC_SHA256_CTX *context)
{
    CC_SHA256_CTX *sha256 = context;
    CC_SHA256_Init(sha256);
    sha256->hash[0] = 0xc1059ed8; sha256->hash[1] = 0x367cd507;
    sha256->hash[2] = 0x3070dd17; sha256->hash[3] = 0xf70e5939;
    sha256->hash[4] = 0xffc00b31; sha256->hash[5] = 0x68581511;
    sha256->hash[6] = 0x64f98fa7; sha256->hash[7] = 0xbefa4fa4;
    return 1;
}

int CC_SHA224_Update(CC_SHA256_CTX *context, const void *data, CC_LONG length)
{
    return CC_SHA256_Update(context, data, length);
}

int CC_SHA224_Final(unsigned char *digest, CC_SHA256_CTX *context)
{
    unsigned char full[CC_SHA256_DIGEST_LENGTH];
    int result = CC_SHA256_Final(full, context);
    memcpy(digest, full, 28);       // CC_SHA224_DIGEST_LENGTH
    return result;
}

// The one-shot digests: Leopard added these beside the Init/Update/Final
// that Tiger has.
unsigned char *CC_SHA1(const void *data, CC_LONG length, unsigned char *digest)
{
    CC_SHA1_CTX context;
    CC_SHA1_Init(&context);
    CC_SHA1_Update(&context, data, length);
    CC_SHA1_Final(digest, &context);
    return digest;
}

unsigned char *CC_SHA256(const void *data, CC_LONG length, unsigned char *digest)
{
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    CC_SHA256_Update(&context, data, length);
    CC_SHA256_Final(digest, &context);
    return digest;
}

#pragma mark Ciphers and HMAC

enum { CPCryptoUnimplemented = -4304 };     // kCCUnimplemented

int32_t CCCryptorCreate(uint32_t operation, uint32_t algorithm, uint32_t options,
                        const void *key, size_t keyLength, const void *iv, void **cryptorOut)
{
    if (cryptorOut != NULL)
        *cryptorOut = NULL;
    return CPCryptoUnimplemented;
}

int32_t CCCryptorUpdate(void *cryptor, const void *dataIn, size_t dataInLength,
                        void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved)
{
    if (dataOutMoved != NULL)
        *dataOutMoved = 0;
    return CPCryptoUnimplemented;
}

int32_t CCCryptorFinal(void *cryptor, void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved)
{
    if (dataOutMoved != NULL)
        *dataOutMoved = 0;
    return CPCryptoUnimplemented;
}

int32_t CCCryptorRelease(void *cryptor) { return 0; }
size_t CCCryptorGetOutputLength(void *cryptor, size_t inputLength, int final) { return 0; }

// HMAC in one call: Leopard's. Built here from the digest Tiger has.
void CCHmac(uint32_t algorithm, const void *key, size_t keyLength,
            const void *data, size_t dataLength, void *macOut)
{
    // kCCHmacAlgSHA1 = 0, SHA256 = 1, SHA384, SHA512, SHA224, MD5
    unsigned char inner[64], outer[64], keyBuffer[64], digest[CC_SHA256_DIGEST_LENGTH];
    size_t blockSize = 64, digestLength = (algorithm == 0) ? CC_SHA1_DIGEST_LENGTH : CC_SHA256_DIGEST_LENGTH;
    size_t i;

    memset(keyBuffer, 0, sizeof keyBuffer);
    if (keyLength > blockSize) {
        if (algorithm == 0)
            CC_SHA1(key, (CC_LONG)keyLength, keyBuffer);
        else
            CC_SHA256(key, (CC_LONG)keyLength, keyBuffer);
    } else if (key != NULL) {
        memcpy(keyBuffer, key, keyLength);
    }
    for (i = 0; i < blockSize; i++) {
        inner[i] = keyBuffer[i] ^ 0x36;
        outer[i] = keyBuffer[i] ^ 0x5c;
    }
    if (algorithm == 0) {
        CC_SHA1_CTX context;
        CC_SHA1_Init(&context);
        CC_SHA1_Update(&context, inner, (CC_LONG)blockSize);
        CC_SHA1_Update(&context, data, (CC_LONG)dataLength);
        CC_SHA1_Final(digest, &context);
        CC_SHA1_Init(&context);
        CC_SHA1_Update(&context, outer, (CC_LONG)blockSize);
        CC_SHA1_Update(&context, digest, (CC_LONG)digestLength);
        CC_SHA1_Final((unsigned char *)macOut, &context);
    } else {
        CC_SHA256_CTX context;
        CC_SHA256_Init(&context);
        CC_SHA256_Update(&context, inner, (CC_LONG)blockSize);
        CC_SHA256_Update(&context, data, (CC_LONG)dataLength);
        CC_SHA256_Final(digest, &context);
        CC_SHA256_Init(&context);
        CC_SHA256_Update(&context, outer, (CC_LONG)blockSize);
        CC_SHA256_Update(&context, digest, (CC_LONG)digestLength);
        CC_SHA256_Final((unsigned char *)macOut, &context);
    }
}

#pragma mark One-line system calls

// Font auto-activation (10.5): Tiger activates fonts its own way.
int ATSFontSetAutoActivationSettingForApplication(int setting, void *bundle) { return 0; }

// Excluding a file from Time Machine, which Tiger does not have.
int CSBackupSetItemExcluded(const void *item, unsigned char exclude, unsigned char excludeByPath) { return 0; }

// Keyboard layouts: Text Input Sources is 10.5. An empty list means "no
// ASCII-capable layout to offer", and the engine keeps the current one.
const void *TISCreateASCIICapableInputSourceList(void) { return NULL; }

// A Carbon event's CGEvent, and the pixel format of a GL context: both are
// reached only through paths that are off on 10.4.
const void *CopyEventCGEvent(const void *event) { return NULL; }
const void *CGLGetPixelFormat(const void *context) { return NULL; }
void *_NSPopUpCarbonMenu3(void) { return NULL; }

// Launch Services privates: what this application is called and what it is
// doing, used for the "opening in" text a download shows.
const void *_LSGetCurrentApplicationASN(void) { return NULL; }
int _LSSetApplicationInformationItem(int sessionID, const void *asn, const void *key,
                                     const void *value, void *outDictionary)
{
    return 0;
}
const void *_kLSDisplayNameKey = "_kLSDisplayNameKey";
