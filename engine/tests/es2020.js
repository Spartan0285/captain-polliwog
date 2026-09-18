// Language features Captain Polliwog adds to JavaScriptCore 604.
// Run with jsc: prints "PASS n" or the failures. Also parsed as a whole
// first, since one unsupported construct fails the entire file.

var failures = [];
var count = 0;
function check(name, actual, expected) {
    count++;
    if (actual !== expected && !(actual !== actual && expected !== expected))
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}

// Nullish coalescing
check("?? null", null ?? 1, 1);
check("?? undefined", undefined ?? 2, 2);
check("?? keeps 0", 0 ?? 3, 0);
check("?? keeps ''", "" ?? 4, "");
check("?? keeps false", false ?? 5, false);
var evaluated = false;
check("?? short-circuits", 1 ?? (evaluated = true), 1);
check("?? right side not evaluated", evaluated, false);
check("?? chain", null ?? undefined ?? 6, 6);
check("?? in condition", (null ?? 0) ? "yes" : "no", "no");

// Optional chaining
var o = { a: { b: { c: 7 } }, arr: [10, 20], f: function () { return this.tag; }, tag: "me", n: null };
check("?. present", o?.a.b.c, 7);
check("?. absent", o.x?.b.c, undefined);
check("?. null", o.n?.b, undefined);
check("?. short-circuits whole chain", o.n?.b.c.d.e, undefined);
check("?.[]", o.arr?.[1], 20);
check("?.[] absent", o.missing?.[0], undefined);
check("?.() method keeps this", o.f?.(), "me");
check("?.() absent method", o.nothing?.(), undefined);
check("?.() on value", (function () { return 8; })?.(), 8);
var nothing = null;
check("?.() null function", nothing?.(), undefined);
check("a?.b()", o?.f(), "me");
check("chain then call", o.a?.b.c.toString(), "7");
var sideEffect = 0;
check("?.[] skips subscript", o.n?.[sideEffect++], undefined);
check("skipped subscript not evaluated", sideEffect, 0);
check("?.() skips arguments", o.nothing?.(sideEffect++), undefined);
check("skipped arguments not evaluated", sideEffect, 0);
check("nested chains", o.a?.b[o.n?.x ?? "c"], 7);
check("delete ?.", delete o.n?.x, true);
var d = { p: { q: 1 } };
check("delete ?. present", delete d.p?.q, true);
check("delete ?. deleted", d.p.q, undefined);
check("keyword property", ({ default: 9 })?.default, 9);
check("conditional, not ?.", true ? .5 : 1, 0.5);
check("typeof ?.", typeof o.n?.x, "undefined");
check("parenthesized ends chain", (function () { try { return (o.n?.b).c; } catch (e) { return "TypeError"; } })(), "TypeError");

var syntaxErrors = ["o?.a = 1", "new o?.a()", "o?.a`t`"];
for (var i = 0; i < syntaxErrors.length; i++) {
    var threw = false;
    try { eval(syntaxErrors[i]); } catch (e) { threw = e instanceof SyntaxError || e instanceof ReferenceError; }
    check("rejects " + syntaxErrors[i], threw, true);
}

// Object rest/spread (ES2018)
var spread = { x: 1, ...{ y: 2, z: 3 } };
check("object spread", spread.x + spread.y + spread.z, 6);
var { x, ...rest } = spread;
check("object rest", Object.keys(rest).join(","), "y,z");

// Optional catch binding (ES2019)
var caught = false;
try { throw 1; } catch { caught = true; }
check("catch without binding", caught, true);

// globalThis (ES2020)
check("globalThis", typeof globalThis, "object");
check("globalThis is the global", globalThis.check === check, true);

// Optional chaining inside functions compiled lazily
function lazy(v) { return v?.w ?? "none"; }
check("lazy function ?. ??", lazy(null), "none");
check("lazy function ?. present", lazy({ w: "w" }), "w");

print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS " + count);
