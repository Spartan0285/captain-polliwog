# Warning about dangerous sites

Captain Polliwog can warn before a page known for phishing or for handing out
malware. The data is Google's Safe Browsing list, but the browser never talks
to Google, and no address ever leaves the Mac.

## Why not ask Google

The obvious implementation — send the URL, ask if it is bad — tells Google
every site you visit. Safari does not do that, and neither does this.

The protocol that avoids it, Safe Browsing Update API v4, keeps a local
database of 32-bit hash prefixes and updates it incrementally with Rice-coded
deltas, then does a second, anonymised lookup when a prefix matches. That is a
lot of machinery to run on a G3, and the incremental format is the fiddliest
part of it.

So the work is split. On a modern Mac, `scripts/make-safebrowsing-list.py`
asks Google for a full update and writes a plain sorted file of 4-byte
prefixes. The PowerPC side only reads that file.

## The file

    "CPSB1"                     5 bytes
    timestamp                   4 bytes, big-endian, seconds since 1970
    count                       4 bytes, big-endian
    prefixes                    count × 4 bytes, big-endian, sorted

It lives at `~/Library/Application Support/Captain Polliwog/safebrowsing.list`.
Sorted, because `CPSafeBrowsing` binary-searches it where it sits in memory:
no parsing, no allocation, a handful of comparisons per lookup. A full list is
a few megabytes — about a million prefixes — which is affordable to keep
resident even on the 256MB Pismo, and a lookup costs about twenty comparisons.

## Building it

```sh
# once: a free key from the Google Cloud console, with "Safe Browsing API" on
export SAFEBROWSING_API_KEY=...
scripts/make-safebrowsing-list.py safebrowsing.list
scp safebrowsing.list pbg4:'~/Library/Application Support/Captain Polliwog/'
```

`--test` writes a tiny list containing Google's published test addresses
instead, which is enough to see the warning page.

## What happens on a match

`CPTab`'s navigation policy asks `CPSafeBrowsing` before every main-frame
load. On a match the request is dropped — nothing of the page is fetched —
and a warning page goes up in its place, carrying the site's own address as
its base URL so the address bar still shows where the load was going.

That last detail is why `CPTab` has a `warningLoadPending` flag: the warning
page arrives back at the same policy method, matches the same list, and would
put itself up again for ever. The stack runs out before the loop does, and the
crash lands somewhere else entirely — in string formatting, in the allocator —
which is a good reminder that a crash inside Foundation usually means the bug
is upstairs.

"Visit Anyway" loads `x-polliwog-proceed:<address>`, which the same method
recognises: the site is added to a list of sites allowed for this run of the
browser, and the real page is loaded. That permission is not written anywhere
and is gone when the browser closes.

## What the warning does not claim

Four bytes of SHA-256 collide: roughly one in four billion per lookup, times
thirty lookups per address, against a list of a million. A page can land on
the warning by coincidence, and the page says so. Checking a full hash would
mean asking Google, which is the thing this design exists to avoid.

The list is also only as fresh as the file. Until the update feed carries it,
that means as fresh as the last time someone ran the script.
