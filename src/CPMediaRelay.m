/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

#import "CPMediaRelay.h"
#import "CPAppDelegate.h"
#import "CPNetworkEngine.h"
#import "CPDebugSnapshot.h"
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
} CPRelayConnection;

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
        if (connection->status < 300 || connection->status >= 400)
            CPSendHeaders(connection);
        return length;
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
    CPSendHeaders(connection);
    // QuickTime has stopped listening: stop fetching.
    return CPSendAll(connection->client, data, length) ? length : 0;
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
    token = CPQueryValue(target, "token");
    url = CPQueryValue(target, "url");
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
