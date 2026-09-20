# PowerEmu Web Accelerator: client guide for Captain Polliwog

*September 2026. Protocol version 1. Companion to PowerEmu's Service Hub
(PowerEmu repository, `app/Sources/PowerEmu/WebAccelerator.swift`).*

## What it is, and what it is not

PowerEmu is the macOS app that runs Tiger and Leopard in a virtual PowerPC Mac.
Its **Service Hub** does work for old Macs that they are too slow or too old to
do themselves. The **Web Accelerator** is one of those services: Captain
Polliwog can hand its HTTP and HTTPS requests to it, and PowerEmu fetches them
with the modern networking of the Mac it runs on.

It is **not** a rendering proxy like the one Basilisk II uses for the 68k
Garden. Captain Polliwog still receives the real HTML, CSS, JavaScript and
images, lays out the page itself and runs its scripts with its own engine.
The accelerator only changes how the bytes get there, and slims them down on
the way:

| Work moved to PowerEmu | Why it helps an old Mac |
|---|---|
| TLS 1.3 and HTTP/2 to the web site | One cheap connection to PowerEmu replaces a TLS handshake per site; a G4 spends a large share of a cold page load on RSA/ECDHE handshakes. |
| WebP, AVIF and HEIC converted to JPEG/PNG | The system WebKit (533/534) can't decode WebP or AVIF at all, so these images are simply missing today. |
| Large images scaled to the size the Mac can show | A 4000-pixel hero image costs a G3 seconds to decode and tens of MB of memory. |
| Ad and tracker requests answered with 204 | Removes much of the third-party JavaScript an old Mac would otherwise run. |
| Text compressed for the hop to the old Mac | Useful over Wi-Fi to a real Mac; free for a virtual one. |
| *(version 2)* JavaScript and CSS lowered to what the engine parses | Modern syntax (`?.`, `??`, classes, `async`) stops scripts from loading at all on WebKit 533. |

Everything is optional for the browser. **If PowerEmu is not running or not
reachable, Captain Polliwog does exactly what it does today** (bundled
OpenSSL + libcurl), with no user-visible difference other than speed.

## Where the accelerator is

| Captain Polliwog runs in… | Address | Pairing |
|---|---|---|
| a PowerEmu virtual Mac | `http://10.0.2.100:7780/` (always this address, in every virtual Mac) | none: only that virtual Mac can reach it |
| a real Mac on the same network | the PowerEmu Mac's name, port **7780**, advertised with Bonjour as `_poweremu-web._tcp` | a pairing code, shown in PowerEmu's Service Hub |

Real Macs can use it only when the PowerEmu user has switched on **Let other
Macs on the network use the Service Hub**.

`10.0.2.100` is a fixed address inside QEMU's user-mode network that PowerEmu
forwards to itself; nothing on the real network answers there, so probing it
from a real Mac fails quickly (no route, or a connection refusal).

## Protocol

### Hello

```
GET /.poweremu/v1/hello HTTP/1.1
Host: 10.0.2.100:7780
X-PowerEmu-Token: 4821-7730          (real Macs only)
```

Answer, `200 OK`, `text/plain`, one `key: value` per line (unknown keys must be
ignored; more will be added):

```
service: PowerEmu Web Accelerator
version: 1
features: tls http2 images block compress
name: Adam's MacBook Air
```

`401` means a pairing code is needed or the one sent is wrong (real Macs only).
Anything else, or no answer within the timeout, means *not available*.

### Fetching

Send the request you would have sent to the web site, to the accelerator, with
the **full URL as the request target** (an HTTP "absolute-form" request, as to
a forward proxy, but for `https` URLs too: the accelerator does the TLS):

```
GET https://en.wikipedia.org/wiki/Power_Macintosh_G4 HTTP/1.1
Host: en.wikipedia.org
User-Agent: ...
Accept: ...
Accept-Encoding: gzip, deflate
Cookie: ...
Referer: ...
X-PowerEmu-Engine: webkit=533.19; js=es5; images=jpeg,png,gif; max-image=1280
X-PowerEmu-Token: 4821-7730          (real Macs only)
X-PowerEmu-Private: 1                (private windows only)
```

* **Any method** works (`GET`, `HEAD`, `POST`, `PUT`, `DELETE`, `OPTIONS`...).
  Request bodies are forwarded as they are (`Content-Length` or chunked).
* **All your headers are forwarded** to the site except the hop-by-hop ones
  (`Connection`, `Keep-Alive`, `Proxy-*`, `TE`, `Upgrade`) and the
  `X-PowerEmu-*` headers. Cookies stay yours: send `Cookie` as now; PowerEmu
  stores none.
* **Redirects are not followed.** A `3xx` comes back as it is, with its
  `Location`, for WebKit to follow as it does today.
* **Range requests** pass through (and the response is then never converted).
* **WebSockets** are not supported in version 1: connect directly.

The answer is the site's status line and headers, with these changes:

* the body has been decoded (the site's `Content-Encoding` removed) and may be
  re-encoded for you with `gzip` or `deflate`, only if your `Accept-Encoding`
  allowed it;
* `Content-Length` or `Transfer-Encoding: chunked` describe the body you get;
* each cookie is its own `Set-Cookie` header;
* `X-PowerEmu: 1` is present on every answer that came through the
  accelerator;
* `X-PowerEmu-Converted: image/webp -> image/jpeg 1280x720` when an image was
  converted (the `Content-Type` is the new one);
* a blocked request is answered `204 No Content` with
  `X-PowerEmu-Blocked: <list name>`.

### When the accelerator itself fails

It answers `502 Bad Gateway` (couldn't reach the site, bad certificate, ...) or
`504 Gateway Timeout`, with `X-PowerEmu-Error: <reason>` and a short text body.
Certificate problems are reported, never ignored:
`X-PowerEmu-Error: certificate: ...`.

### Describing the engine: `X-PowerEmu-Engine`

Semicolon-separated `key=value` pairs; unknown keys are ignored.

| Key | Meaning | Examples |
|---|---|---|
| `webkit` | the engine's WebKit version | `533.19` (Tiger), `534.50` (Leopard), `604.1` (the 2018 engine) |
| `js` | newest JavaScript the engine *parses* (version 2 lowers anything newer) | `es5` for 533/534, `es2017` for 604 |
| `images` | image types the engine decodes | `jpeg,png,gif` (533/534); add `webp` if an engine gains it |
| `max-image` | longest edge, in pixels, worth sending; `0` means never resize | the screen's longest side, e.g. `1280` on a 12" iBook |

Send it on every request: PowerEmu keeps no per-client state.

## Adding it to Captain Polliwog

All of it fits in the networking layer, below WebKit: `CPNetworkTask` already
builds every request with libcurl. WebKit keeps seeing the original `https://`
URLs, so redirects, cookies, `CPHTTPCache` and security origins behave as now.

### 1. `CPAccelerator`: finding it

A small class, like `CPMediaRelay`, that answers one question quickly:
*should this request go to the accelerator, and where?*

```objc
@interface CPAccelerator : NSObject
+ (void)start;                         // at launch; also on network changes
+ (NSString *)baseURL;                 // nil when not available
+ (BOOL)shouldRoute:(NSURL *)url;      // YES for http(s) when available and allowed
+ (void)markFailed;                    // a request couldn't reach it: stop using it for a while
+ (NSString *)engineHeader;            // the X-PowerEmu-Engine value for this Mac
+ (NSString *)token;                   // pairing code for real Macs, or nil
@end
```

Discovery, in order, on a background thread:

1. `hello` to `10.0.2.100:7780` with a **300 ms connect timeout**
   (`CURLOPT_CONNECTTIMEOUT_MS`). Success means we are in a PowerEmu virtual
   Mac.
2. Otherwise browse `_poweremu-web._tcp` with `NSNetServiceBrowser` (Tiger has
   it) for up to 2 seconds, resolve, and `hello` with the stored pairing code.
   Remember the last host that worked and try it first next time.
3. Otherwise: not available. Try again on the next network change
   (`SCDynamicStore` notification for `State:/Network/Global/IPv4`) and at most
   every 5 minutes.

`shouldRoute:` returns NO when the accelerator is unavailable or marked
failed, when the user switched it off, for `localhost`/`127.0.0.1` (that is
`CPMediaRelay`), for `.local` hosts and literal private-network addresses
(the old Mac can reach those directly), and for `ws:`/`wss:`.

### 2. `CPNetworkTask`: routing a request

Where the easy handle is configured (today around
`curl_easy_setopt(easy, CURLOPT_URL, ...)`):

```objc
NSURL *url = [request URL];
BOOL viaPowerEmu = [CPAccelerator shouldRoute:url];
if (viaPowerEmu) {
    // Connect to PowerEmu, but ask for the real URL.
    curl_easy_setopt(easy, CURLOPT_URL, [[CPAccelerator baseURL] UTF8String]);
    curl_easy_setopt(easy, CURLOPT_REQUEST_TARGET, [[url absoluteString] UTF8String]);
    headers = curl_slist_append(headers,
        [[NSString stringWithFormat:@"Host: %@", CPHostHeader(url)] UTF8String]);
    headers = curl_slist_append(headers,
        [[@"X-PowerEmu-Engine: " stringByAppendingString:[CPAccelerator engineHeader]] UTF8String]);
    if ([CPAccelerator token])
        headers = curl_slist_append(headers,
            [[@"X-PowerEmu-Token: " stringByAppendingString:[CPAccelerator token]] UTF8String]);
    if (isPrivate)
        headers = curl_slist_append(headers, "X-PowerEmu-Private: 1");
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT_MS, 1500L);
} else {
    curl_easy_setopt(easy, CURLOPT_URL, [[url absoluteString] UTF8String]);
}
```

Notes:

* `CPHostHeader(url)` is the host, plus `:port` when the URL has a
  non-default port.
* `CURLOPT_REQUEST_TARGET` needs libcurl 7.55 or later (Captain Polliwog
  bundles 8.22). curl then sends `GET https://... HTTP/1.1` to PowerEmu.
* Keep `CURLOPT_ACCEPT_ENCODING` as it is; PowerEmu only uses `gzip`/`deflate`
  and only if they were offered.
* Keep reusing connections (the curl share/multi handle): all requests go to
  one host now, so a handful of keep-alive connections carry a whole page.
* Downloads (`CPDownload`) can use the same path; large bodies stream.

### 3. Falling back

In the completion path of `CPNetworkTask`:

| What happened | Do |
|---|---|
| connect failed / timed out to PowerEmu (`CURLE_COULDNT_CONNECT`, `CURLE_OPERATION_TIMEDOUT` before any response byte) | `[CPAccelerator markFailed]`, then **run the same request again directly**. Safe for every method: nothing reached the site. |
| `502`/`504` with `X-PowerEmu-Error`, method `GET`/`HEAD` | retry once directly (the direct path shows the user its own error if the site is really down) |
| `502`/`504`, other methods | give the error to WebKit; don't resubmit a POST |
| `401` from PowerEmu (pairing code no longer valid) | `markFailed`, retry directly, and show "PowerEmu needs a new pairing code" in the accelerator preferences |
| anything else | it is the site's answer: hand it to WebKit |

`markFailed` stops routing for 60 seconds, then the next `shouldRoute:` does a
fresh `hello`.

### 4. `X-PowerEmu-Engine` values

```objc
+ (NSString *)engineHeader
{
    // "533.19.4" -> "533.19"; the engine in use (system or 604).
    NSString *wk = CPEngineWebKitVersion();
    BOOL modern = [wk intValue] >= 604;
    NSRect screen = [[NSScreen mainScreen] frame];
    int edge = (int)MAX(screen.size.width, screen.size.height);
    return [NSString stringWithFormat:@"webkit=%@; js=%@; images=jpeg,png,gif; max-image=%d",
            wk, modern ? @"es2017" : @"es5", edge];
}
```

### 5. Preferences and interface

* **Preferences → Advanced → "Speed up browsing with PowerEmu": Automatic /
  Off** (default Automatic), with the status underneath: *Using PowerEmu on
  Adam's MacBook Air* / *PowerEmu not found* / *PowerEmu needs a pairing
  code: [ Enter Code… ]*.
* The pairing code (`4821-7730` form) is shown in PowerEmu's Service Hub; keep
  it with `CPKeychain`.
* **The lock icon.** Through the accelerator it is PowerEmu that checked the
  site's certificate. Keep the lock for `https` pages, and say so in the
  page-security popover: *"Verified by PowerEmu on Adam's MacBook Air"*.
* Private windows send `X-PowerEmu-Private: 1`; PowerEmu keeps nothing about
  those requests (no log line, no cache).

### 6. Things to leave alone

* **`CPMediaRelay`** keeps serving QuickTime from `127.0.0.1`. When the
  accelerator is available, the relay's own curl requests can go through it
  too: same code path.
* **`CPHTTPCache`** keeps caching what comes back. A converted image is cached
  converted, which is what the Mac wants anyway.
* **Cookies, history, bookmarks** are untouched: PowerEmu sees cookies in
  transit but stores none.

## Testing

From a modern Mac on the same network (curl 7.55 or later; PowerEmu's
"Let other Macs on the network use the Service Hub" on), curl can play the
browser:

```sh
curl -s -H 'X-PowerEmu-Token: 4821-7730' http://adams-macbook-air.local:7780/.poweremu/v1/hello
curl -s -o /dev/null -D - -H 'X-PowerEmu-Token: 4821-7730' \
     --request-target https://www.gstatic.com/webp/gallery/1.webp -H 'Host: www.gstatic.com' \
     -H 'X-PowerEmu-Engine: webkit=533.19; js=es5; images=jpeg,png,gif; max-image=800' \
     http://adams-macbook-air.local:7780/
# -> 200, Content-Type: image/jpeg, X-PowerEmu-Converted: image/webp -> image/jpeg 550x368
```

Inside a PowerEmu virtual Mac, Tiger's own curl (7.13) is too old for
`--request-target`; Python 2.3 does it:

```sh
python -c '
import httplib
c = httplib.HTTPConnection("10.0.2.100", 7780)
c.putrequest("GET", "https://en.wikipedia.org/wiki/Power_Mac_G4", skip_host=1)
c.putheader("Host", "en.wikipedia.org")
c.putheader("X-PowerEmu-Engine", "webkit=533.19; js=es5; images=jpeg,png,gif; max-image=1024")
c.endheaders()
r = c.getresponse(); print r.status, r.getheader("x-powerEmu"), len(r.read())'
```

Check list for the Captain Polliwog side:

1. PowerEmu running: pages load, `X-PowerEmu: 1` on responses (log it in debug
   builds), WebP images on e.g. a news site appear.
2. Quit PowerEmu mid-session: the next page load falls back without an error
   page (connect refused → direct).
3. Not in a VM and no PowerEmu on the network: the 300 ms probe costs nothing
   visible at launch.
4. POST a form while PowerEmu is quitting: no double submission.
5. Private window: nothing about it in PowerEmu's Service Hub activity.
6. A site with a bad certificate (badssl.com): an error, not a silent load.

## Version 2 (planned)

* **JavaScript and CSS lowering** by the `js=` level: PowerEmu runs a bundled
  compiler (SWC for JavaScript, Lightning CSS for CSS) over scripts and
  stylesheets and caches the results by content hash. Pages that pin scripts
  with Subresource Integrity (`integrity="sha384-..."`) would reject a
  rewritten script, so PowerEmu also removes `integrity` attributes from HTML
  it passes through when it rewrites the resources they cover.
* A shared cache across all the old Macs using one PowerEmu.
* `X-PowerEmu-Engine: webp` etc. as engines gain formats.
