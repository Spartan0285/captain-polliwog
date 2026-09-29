/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPMediaRelay.h"
#import "CPAppDelegate.h"
#import "CPNetworkEngine.h"
#import "CPDebugSnapshot.h"
#import "CPSettings.h"
#include <curl/curl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define CPRequestLimit 16384

static char CPRelayToken[33];
static char *CPCertificateBundle;
static char *CPUserAgent;

typedef struct {
    int client;
    BOOL headersSent;
    BOOL headRequest;
    long status;
    char headers[4096];         // the final response's headers to pass on
    size_t headersLength;
    // The chunked path below: what the probe learned, and whether the
    // headers this connection sends are ours rather than the server's.
    BOOL synthesised;
    BOOL discardBody;
    long long total;            // -1 when the server did not say
    char contentType[160];
} CPRelayConnection;

// How much to ask an upstream server for at once.
//
// googlevideo refuses a range larger than somewhere between 4MB and 10MB with
// 403, and refuses an open-ended range - Range: bytes=0- - outright, which is
// exactly what VLC asks for. Measured against one file: 1KB, 64KB, 256KB, 1MB
// and 4MB all answered 206; 10MB and the whole 25MB file answered 403. So a
// request for the whole thing is served as a series of bounded ones, joined
// into a single response the player sees as one stream.
//
// This is not YouTube-specific behaviour worth special-casing: a bounded
// range is something any server that supports ranges will honour, and one
// that does not support them at all falls back to the plain path below.
#define CPRelayChunk (2 * 1024 * 1024)

static BOOL CPSendAll(int socketFD, const char *data, size_t length)
{
    while (length > 0) {
        ssize_t sent = send(socketFD, data, length, 0);
        if (sent <= 0)
            return NO;
        data += sent;
        length -= sent;
    }
    return YES;
}

static void CPSendHeaders(CPRelayConnection *connection)
{
    char statusLine[64];
    if (connection->headersSent)
        return;
    connection->headersSent = YES;
    snprintf(statusLine, sizeof(statusLine), "HTTP/1.1 %ld %s\r\n", connection->status,
             connection->status == 206 ? "Partial Content" : connection->status < 300 ? "OK" : "Error");
    CPSendAll(connection->client, statusLine, strlen(statusLine));
    CPSendAll(connection->client, connection->headers, connection->headersLength);
    CPSendAll(connection->client, "Connection: close\r\n\r\n", 21);
}

static size_t CPRelayHeader(char *data, size_t size, size_t count, void *context)
{
    CPRelayConnection *connection = context;
    size_t length = size * count;
    static const char *passed[] = {
        "content-type:", "content-length:", "content-range:", "accept-ranges:", "last-modified:", "etag:", NULL
    };
    unsigned i;

    // A new response (after a redirect): start over.
    if (length > 5 && strncmp(data, "HTTP/", 5) == 0) {
        const char *space = memchr(data, ' ', length);
        connection->status = space != NULL ? strtol(space + 1, NULL, 10) : 502;
        connection->headersLength = 0;
        return length;
    }
    if (length <= 2) {
        // The end of a response's headers; redirects are followed, not passed.
        if (!connection->synthesised && (connection->status < 300 || connection->status >= 400))
            CPSendHeaders(connection);
        return length;
    }
    // What the probe is after: the total length, which only Content-Range
    // carries, and the type, which the synthesised headers have to repeat.
    if (length > 14 && strncasecmp(data, "content-range:", 14) == 0) {
        const char *slash = memchr(data, '/', length);
        if (slash != NULL)
            connection->total = strtoll(slash + 1, NULL, 10);
    }
    if (length > 13 && strncasecmp(data, "content-type:", 13) == 0) {
        const char *value = data + 13;
        size_t valueLength = length - 13;
        while (valueLength > 0 && (*value == ' ' || *value == '\t')) { value++; valueLength--; }
        while (valueLength > 0 && (value[valueLength - 1] == '\r' || value[valueLength - 1] == '\n'))
            valueLength--;
        if (valueLength < sizeof(connection->contentType)) {
            memcpy(connection->contentType, value, valueLength);
            connection->contentType[valueLength] = 0;
        }
    }
    for (i = 0; passed[i] != NULL; i++) {
        size_t nameLength = strlen(passed[i]);
        if (length > nameLength && strncasecmp(data, passed[i], nameLength) == 0
            && connection->headersLength + length < sizeof(connection->headers)) {
            memcpy(connection->headers + connection->headersLength, data, length);
            connection->headersLength += length;
        }
    }
    return length;
}

static size_t CPRelayData(char *data, size_t size, size_t count, void *context)
{
    CPRelayConnection *connection = context;
    size_t length = size * count;
    // The probe only wants the headers; its body is read and dropped so the
    // connection closes cleanly.
    if (connection->discardBody)
        return length;
    if (!connection->synthesised)
        CPSendHeaders(connection);
    // QuickTime has stopped listening: stop fetching.
    return CPSendAll(connection->client, data, length) ? length : 0;
}

// One upstream request for a bounded byte range. Returns the status, or 0 if
// the client went away mid-stream.
static long CPRelayFetch(const char *url, CPRelayConnection *connection,
                         long long start, long long end, BOOL bodyToClient)
{
    CURL *easy = curl_easy_init();
    char range[64];
    long status = 0;

    if (easy == NULL)
        return 0;
    snprintf(range, sizeof(range), "%lld-%lld", start, end);
    connection->discardBody = !bodyToClient;
    curl_easy_setopt(easy, CURLOPT_URL, url);
    curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(easy, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(easy, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_1_1);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(easy, CURLOPT_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_2);
    if (CPCertificateBundle != NULL)
        curl_easy_setopt(easy, CURLOPT_CAINFO, CPCertificateBundle);
    if (CPUserAgent != NULL)
        curl_easy_setopt(easy, CURLOPT_USERAGENT, CPUserAgent);
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT, 30L);
    curl_easy_setopt(easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(easy, CURLOPT_LOW_SPEED_TIME, 60L);
    curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, CPRelayHeader);
    curl_easy_setopt(easy, CURLOPT_HEADERDATA, connection);
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, CPRelayData);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, connection);
    curl_easy_setopt(easy, CURLOPT_RANGE, range);
    curl_easy_perform(easy);
    curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_cleanup(easy);
    connection->discardBody = NO;
    return status;
}

// Headers for the whole response, written by us rather than copied from the
// server: the server is answering for one chunk and the player is being told
// about the entire stream.
static void CPSendSynthesisedHeaders(CPRelayConnection *connection, BOOL clientAskedForRange,
                                     long long start, long long end, long long total)
{
    char head[512];
    int length;

    connection->headersSent = YES;
    length = snprintf(head, sizeof(head),
        "HTTP/1.1 %s\r\n"
        "Content-Type: %s\r\n"
        "Accept-Ranges: bytes\r\n"
        "Content-Length: %lld\r\n",
        clientAskedForRange ? "206 Partial Content" : "200 OK",
        connection->contentType[0] != 0 ? connection->contentType : "application/octet-stream",
        end - start + 1);
    if (clientAskedForRange && length > 0 && (size_t)length < sizeof(head))
        length += snprintf(head + length, sizeof(head) - length,
                           "Content-Range: bytes %lld-%lld/%lld\r\n", start, end, total);
    if (length > 0 && (size_t)length < sizeof(head))
        length += snprintf(head + length, sizeof(head) - length, "Connection: close\r\n\r\n");
    if (length > 0)
        CPSendAll(connection->client, head, strlen(head));
}

static void CPSendError(int client, const char *status)
{
    char response[160];
    snprintf(response, sizeof(response), "HTTP/1.1 %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", status);
    CPSendAll(client, response, strlen(response));
}

// The value of a query parameter, percent-decoded, or NULL.
static char *CPQueryValue(const char *target, const char *name)
{
    const char *query = strchr(target, '?');
    size_t nameLength = strlen(name);
    while (query != NULL) {
        query++;
        if (strncmp(query, name, nameLength) == 0 && query[nameLength] == '=') {
            const char *start = query + nameLength + 1;
            size_t length = strcspn(start, "&");
            char *value = malloc(length + 1), *out = value;
            size_t i;
            for (i = 0; i < length; i++) {
                if (start[i] == '%' && i + 2 < length) {
                    char hex[3] = { start[i + 1], start[i + 2], 0 };
                    *out++ = (char)strtol(hex, NULL, 16);
                    i += 2;
                } else
                    *out++ = start[i] == '+' ? ' ' : start[i];
            }
            *out = 0;
            return value;
        }
        query = strchr(query, '&');
    }
    return NULL;
}

// base64url, for the address an external player is given.
//
// VLC percent-encodes the MRL it is handed before it sends it: characters
// that are already escapes come back as %25XX, so a URL passed in as
// url=https%3A%2F%2F... arrives here as url=https%253A%252F%252F..., decodes
// once to https%3A%2F%2F... - which is not an address - and is refused. It
// looked exactly like the relay rejecting the player's token. Measured: the
// same address fetched by curl 206, and with every % doubled 403.
//
// So players are given url64= instead, in an alphabet with nothing in it
// that any encoder would want to touch. url= stays for the engine, which
// builds its own relay addresses and does not re-encode them.
static char *CPBase64URLDecode(const char *text)
{
    static const char *alphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    size_t length = strlen(text);
    char *out = malloc(length + 4);
    size_t i, held = 0;
    unsigned accumulator = 0;
    char *write = out;

    if (out == NULL)
        return NULL;
    for (i = 0; i < length; i++) {
        const char *found = strchr(alphabet, text[i]);
        if (found == NULL || text[i] == 0) {
            free(out);
            return NULL;       // not our alphabet: refuse rather than guess
        }
        accumulator = (accumulator << 6) | (unsigned)(found - alphabet);
        held += 6;
        if (held >= 8) {
            held -= 8;
            *write++ = (char)((accumulator >> held) & 0xff);
        }
    }
    *write = 0;
    return out;
}

static void *CPRelayServe(void *argument)
{
    int client = (int)(long)argument;
    char request[CPRequestLimit + 1];
    size_t received = 0;
    char method[16], target[CPRequestLimit];
    char *url = NULL, *token = NULL, *rangeHeader, *range = NULL;
    CPRelayConnection connection;
    CURL *easy;

    // The request's head.
    while (received < CPRequestLimit) {
        ssize_t got = recv(client, request + received, CPRequestLimit - received, 0);
        if (got <= 0)
            break;
        received += got;
        request[received] = 0;
        if (strstr(request, "\r\n\r\n") != NULL)
            break;
    }
    request[received] = 0;
    if (sscanf(request, "%15s %16383s", method, target) != 2 || (strcmp(method, "GET") != 0 && strcmp(method, "HEAD") != 0)) {
        CPSendError(client, "400 Bad Request");
        close(client);
        return NULL;
    }
    // Two address forms.
    //
    // The engine's is a query: /media?token=..&url=<percent-escaped>. The
    // external players' is a path: /media/<token>/<base64url>.<ext> - because
    // VLC works out what a --input-slave contains from its file extension,
    // and a query string leaves it with nothing to look at. Handed an address
    // with no extension it guesses "audio-es", hands an MP4 to the raw
    // elementary-stream demuxer, and drops the sound with "failed to add ..
    // as slave" while the video plays perfectly.
    if (strncmp(target, "/media/", 7) == 0) {
        const char *rest = target + 7;
        const char *slash = strchr(rest, '/');
        if (slash != NULL) {
            size_t tokenLength = (size_t)(slash - rest);
            const char *encoded = slash + 1;
            const char *dot = strrchr(encoded, '.');
            size_t encodedLength = dot != NULL ? (size_t)(dot - encoded) : strlen(encoded);
            char *copy = malloc(encodedLength + 1);
            token = malloc(tokenLength + 1);
            if (token != NULL) {
                memcpy(token, rest, tokenLength);
                token[tokenLength] = 0;
            }
            if (copy != NULL) {
                memcpy(copy, encoded, encodedLength);
                copy[encodedLength] = 0;
                url = CPBase64URLDecode(copy);
                free(copy);
            }
        }
    }
    if (token == NULL)
        token = CPQueryValue(target, "token");
    if (url == NULL)
        url = CPQueryValue(target, "url");
    if (url == NULL) {
        char *encoded = CPQueryValue(target, "url64");
        if (encoded != NULL) {
            url = CPBase64URLDecode(encoded);
            free(encoded);
        }
    }
    if (token == NULL || strcmp(token, CPRelayToken) != 0 || url == NULL
        || (strncmp(url, "https://", 8) != 0 && strncmp(url, "http://", 7) != 0)) {
        CPSendError(client, "403 Forbidden");
        free(token);
        free(url);
        close(client);
        return NULL;
    }
    rangeHeader = strcasestr(request, "\r\nRange: bytes=");
    if (rangeHeader != NULL) {
        size_t length;
        rangeHeader += strlen("\r\nRange: bytes=");
        length = strcspn(rangeHeader, "\r\n");
        range = malloc(length + 1);
        memcpy(range, rangeHeader, length);
        range[length] = 0;
    }

    memset(&connection, 0, sizeof(connection));
    connection.client = client;
    connection.headRequest = strcmp(method, "HEAD") == 0;
    connection.status = 502;
    connection.total = -1;

    // What the client asked for. An absent Range means the whole file, which
    // still has to be fetched in bounded pieces.
    {
        long long start = 0, end = -1;
        BOOL askedForRange = range != NULL;
        long probeStatus;

        if (range != NULL) {
            char *dash = strchr(range, '-');
            start = strtoll(range, NULL, 10);
            if (dash != NULL && dash[1] != 0)
                end = strtoll(dash + 1, NULL, 10);
        }
        // Only when the client did not name an end. A player that asks for a
        // definite stretch of bytes gets exactly the request it asked for,
        // passed straight through as it always was - that is what the engine
        // does for the video in a page, and it works, so it is left alone.
        // The chunked path below exists for the other kind of asking: no
        // Range at all, or Range: bytes=0-, which is what VLC sends and what
        // googlevideo answers with 403.
        if (end >= 0)
            goto plain;

        // A small bounded request, to learn the length and the type. Its body
        // is dropped. This is the one extra round trip the chunked path costs.
        connection.synthesised = YES;
        probeStatus = CPRelayFetch(url, &connection, start, start + 1023, NO);
        if (probeStatus == 206 && connection.total > 0 && start < connection.total) {
            long long position;
            if (end < 0 || end >= connection.total)
                end = connection.total - 1;
            CPSendSynthesisedHeaders(&connection, askedForRange, start, end, connection.total);
            if (!connection.headRequest) {
                for (position = start; position <= end; position += CPRelayChunk) {
                    long long last = position + CPRelayChunk - 1;
                    long status;
                    if (last > end)
                        last = end;
                    status = CPRelayFetch(url, &connection, position, last, YES);
                    // 0 means the player stopped reading; anything else out of
                    // the 2xx range means the server changed its mind, and
                    // there is no way to tell the player now - the headers
                    // went out long ago. Stopping is all that is left.
                    if (status < 200 || status >= 300)
                        break;
                }
            }
            free(range);
            free(token);
            free(url);
            close(client);
            return NULL;
        }
        // The server does not do ranges, or refused the probe. Fall through to
        // one plain request and pass its own headers on, which is what every
        // server that behaves normally gets.
        connection.synthesised = NO;
        connection.headersSent = NO;
        connection.headersLength = 0;
        connection.status = 502;
    }
plain:

    easy = curl_easy_init();
    curl_easy_setopt(easy, CURLOPT_URL, url);
    curl_easy_setopt(easy, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(easy, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(easy, CURLOPT_HTTP_VERSION, (long)CURL_HTTP_VERSION_1_1);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(easy, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(easy, CURLOPT_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_2);
    if (CPCertificateBundle != NULL)
        curl_easy_setopt(easy, CURLOPT_CAINFO, CPCertificateBundle);
    if (CPUserAgent != NULL)
        curl_easy_setopt(easy, CURLOPT_USERAGENT, CPUserAgent);
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT, 30L);
    curl_easy_setopt(easy, CURLOPT_LOW_SPEED_LIMIT, 1L);
    curl_easy_setopt(easy, CURLOPT_LOW_SPEED_TIME, 60L);
    curl_easy_setopt(easy, CURLOPT_HEADERFUNCTION, CPRelayHeader);
    curl_easy_setopt(easy, CURLOPT_HEADERDATA, &connection);
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, CPRelayData);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, &connection);
    if (range != NULL)
        curl_easy_setopt(easy, CURLOPT_RANGE, range);
    if (connection.headRequest)
        curl_easy_setopt(easy, CURLOPT_NOBODY, 1L);

    curl_easy_perform(easy);
    if (!connection.headersSent)
        CPSendError(client, "502 Bad Gateway");
    curl_easy_cleanup(easy);

    free(range);
    free(token);
    free(url);
    close(client);
    return NULL;
}

static void *CPRelayAccept(void *argument)
{
    int server = (int)(long)argument;
    while (1) {
        int client = accept(server, NULL, NULL);
        int on = 1;
        pthread_t thread;
        pthread_attr_t attributes;
        if (client < 0)
            continue;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
        pthread_attr_init(&attributes);
        pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&thread, &attributes, CPRelayServe, (void *)(long)client) != 0)
            close(client);
        pthread_attr_destroy(&attributes);
    }
    return NULL;
}

@implementation CPMediaRelay

+ (void)start
{
    static BOOL started = NO;
    struct sockaddr_in address;
    socklen_t addressLength = sizeof(address);
    int server, on = 1;
    unsigned i;
    pthread_t thread;
    pthread_attr_t attributes;
    NSString *bundle;

    if (started)
        return;
    started = YES;
    // Without the relay, video from sites that require modern TLS doesn't
    // play: the Performance setting for video.
    if (![[CPSettings sharedSettings] playsVideo])
        return;

    for (i = 0; i < 32; i++)
        CPRelayToken[i] = "0123456789abcdef"[arc4random() % 16];
    CPRelayToken[32] = 0;
    bundle = [CPNetworkEngine certificateBundlePath];
    if (bundle != nil)
        CPCertificateBundle = strdup([bundle fileSystemRepresentation]);
    CPUserAgent = strdup([[NSString stringWithFormat:@"Mozilla/5.0 (Macintosh; PPC Mac OS X) AppleWebKit (KHTML, like Gecko) %@",
                           [CPAppDelegate userAgentApplicationName]] UTF8String]);

    server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0)
        return;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 16) != 0
        || getsockname(server, (struct sockaddr *)&address, &addressLength) != 0) {
        close(server);
        return;
    }

    pthread_attr_init(&attributes);
    pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
    pthread_create(&thread, &attributes, CPRelayAccept, (void *)(long)server);
    pthread_attr_destroy(&attributes);

    // Registered, not stored: gone when the app quits, as the relay is.
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:ntohs(address.sin_port)], @"CPMediaRelayPort",
        [NSString stringWithUTF8String:CPRelayToken], @"CPMediaRelayToken",
        nil]];
    if (CPDebugLogging())
        NSLog(@"Captain Polliwog: media relay on port %d", ntohs(address.sin_port));
}

@end
