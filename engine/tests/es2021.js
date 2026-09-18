// Logical assignment (ES2021) and await after a unary operator, as Captain
// Polliwog adds them to JavaScriptCore 604. Run with jsc: prints "PASS n"
// or the failures.

var failures = [];
var count = 0;
function check(name, actual, expected) {
    count++;
    if (actual !== expected)
        failures.push(name + ": got " + String(actual) + ", expected " + String(expected));
}

// On variables, local and global.
var g = null;
g ??= 1;
check("global ??=", g, 1);
g ??= 2;
check("global ??= keeps value", g, 1);
(function () {
    var a = 0, b = 1, c = null, d = "x";
    a ||= 5;
    b &&= 7;
    c ??= 9;
    d ??= "unused";
    check("||= on falsy", a, 5);
    check("&&= on truthy", b, 7);
    check("??= on null", c, 9);
    check("??= keeps string", d, "x");
    var zero = 0;
    zero ??= 3;
    check("??= keeps 0", zero, 0);
    var f = false;
    f &&= "never";
    check("&&= on falsy keeps", f, false);
    check("result of ||=", (a ||= 99), 5);
    let fn;
    fn ||= function () {};
    check("anonymous function gets the name", fn.name, "fn");
})();

// Short circuit: the right side runs only when it assigns.
var calls = 0;
function bump() { calls++; return "bumped"; }
var t = "set";
t ||= bump();
t ??= bump();
check("right side skipped", calls, 0);
var u;
u ??= bump();
check("right side run once", calls, 1);

// On properties, with the object evaluated once.
var objectEvaluations = 0;
var o = { a: null, b: 0, c: 1 };
function getO() { objectEvaluations++; return o; }
getO().a ??= "A";
getO().b ||= "B";
getO().c &&= "C";
check("dot ??=", o.a, "A");
check("dot ||=", o.b, "B");
check("dot &&=", o.c, "C");
check("object evaluated once each", objectEvaluations, 3);

var keyEvaluations = 0;
function key() { keyEvaluations++; return "k"; }
var p = {};
p[key()] ??= 1;
p[key()] ??= 2;
check("bracket ??=", p.k, 1);
check("key evaluated once each", keyEvaluations, 2);

// No set when short-circuited: setters and read-only properties.
var sets = 0;
var withSetter = { get v() { return 1; }, set v(x) { sets++; } };
withSetter.v ||= 2;
check("setter not called when short-circuited", sets, 0);
withSetter.v &&= 3;
check("setter called when assigning", sets, 1);
var frozen = Object.freeze({ x: 1 });
frozen.x ||= 2;
check("no write to frozen when short-circuited", frozen.x, 1);
const constant = 1;
var constError = "none";
try { constant ||= 2; } catch (e) { constError = "threw"; }
check("const short-circuit does not throw", constError, "none");
try { constant &&= 2; } catch (e) { constError = e.constructor.name; }
check("const assignment throws", constError, "TypeError");

// Classes: private fields and super.
class Cache {
    #store = null;
    get() { return this.#store ??= { made: true }; }
}
var cache = new Cache();
check("private field ??=", cache.get() === cache.get(), true);

// await after unary operators.
var awaitResults = [];
async function unaryAwait() {
    awaitResults.push(String(void await Promise.resolve(1)));
    awaitResults.push(!await Promise.resolve(0));
    awaitResults.push(typeof await Promise.resolve("s"));
    awaitResults.push(-await Promise.resolve(4));
    return awaitResults.join(",");
}
var asyncResult = "";
unaryAwait().then(function (r) { asyncResult = r; });
drainMicrotasks();
check("await after unary operators", asyncResult, "undefined,true,string,-4");

// Numeric separators.
check("decimal separators", 1_000_000, 1000000);
check("fraction separators", 1_0.2_5, 10.25);
check("exponent separators", 1e1_0, 1e10);
check("hex separators", 0xFF_FF, 65535);
check("binary separators", 0b1010_1010, 170);
check("octal separators", 0o7_7, 63);
check("big decimal", 12_345_678_901_234, 12345678901234);

// Syntax that must still be rejected.
var syntaxErrors = ["1 ||= 2", "f() &&= 1", "a ?? = 1", "1__0", "1_", "0x_1"];
for (var i = 0; i < syntaxErrors.length; i++) {
    var threw = false;
    try { eval(syntaxErrors[i]); } catch (e) { threw = e instanceof SyntaxError || e instanceof ReferenceError; }
    check("rejects " + syntaxErrors[i], threw, true);
}

print(failures.length ? "FAIL\n" + failures.join("\n") : "PASS " + count);
