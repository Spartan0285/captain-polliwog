// Runs the same work twice over, once through the optimizing compiler and
// once not, and reports anything that comes out different. On a big-endian
// 32-bit machine the DFG has never run before, and the way it goes wrong is
// not a crash but a wrong number: a value read from the half of a 64-bit
// field that PowerPC keeps at the other address.
//
//   jsc --useDFGJIT=false dfg-differential.js > a
//   jsc --useDFGJIT=true --thresholdForOptimizeAfterWarmUp=10 \
//       --thresholdForOptimizeSoon=10 --thresholdForJITAfterWarmUp=5 dfg-differential.js > b
//   diff a b
//
// Every case runs hot enough to be compiled and then keeps running, so an
// answer that only goes wrong after the compiler takes over still shows up.

var WARM = 300;

// Each case runs hot enough to be compiled and then keeps running, and every
// answer it gives along the way is folded into one number. A single wrong
// value anywhere in three hundred iterations changes that number, so the two
// runs differ by one line rather than by three thousand.
function run(name, f)
{
    var hash = 0, first = null, last = null;
    for (var i = 0; i < WARM; i++) {
        var r = String(f(i));
        if (i === 0)
            first = r;
        last = r;
        for (var c = 0; c < r.length; c++)
            hash = ((hash * 31 + r.charCodeAt(c)) & 0x3fffffff);
    }
    print(name + "\t" + hash + "\t" + first.substring(0, 60) + "\t" + last.substring(0, 60));
}
// The harness itself stays out of the compiler, so that a case that goes
// wrong is reported rather than swallowed.
if (typeof noDFG === "function")
    noDFG(run);

// Integers that leave the range the compiler speculates on.
run("int-overflow", function (k) {
    var a = 0x3fffffff + (k % 3), b = a * 3, c = (a + b) | 0, d = a * a;
    return [a, b, c, d, a + 1, -a - 1, (a << 2), (a >>> 1), (a >> 1)].join(",");
});

// The sign of zero, infinities and NaN survive boxing and unboxing.
run("special-doubles", function () {
    var z = -0, p = 0, n = 0 / 0, i = 1 / 0, m = -1 / 0;
    return [1 / z, 1 / p, n === n, i, m, Math.min(-0, 0), Math.max(-0, 0),
            String(n), z === p, Object.is ? Object.is(-0, 0) : "n/a"].join(",");
});

// Doubles that are exactly representable, and ones that are not.
run("double-math", function (k) {
    var x = k / 7, y = Math.sqrt(2) * x, z = x * 1e308 * 10;
    return [x.toFixed(6), y.toFixed(6), z, (x + y) * 0.5, Math.pow(x, 3).toFixed(3),
            (y % 3).toFixed(6), Math.round(y * 1000) / 1000].join(",");
});

// Bit operations: where the win was, and where a 32-bit value read from the
// wrong word shows up immediately.
run("bitops", function (k) {
    var h = 0x811c9dc5 ^ k;
    for (var i = 0; i < 64; i++) { h = (h ^ i) * 16777619; h = (h >>> 0) ^ (h >>> 13); }
    var s = h | 0;
    return [h >>> 0, s, s >> 3, s >>> 3, s << 3, ~s, s & 0xffff, s | 0x10000, s ^ -1].join(",");
});

// Conversions between the two number representations the engine keeps.
run("int-double-round-trip", function (k) {
    var a = [];
    var values = [0, 1, -1, k, -k, 2147483647, -2147483648, 1073741824, 0.5, -0.5, 1e21, 1e-7];
    for (var i = 0; i < values.length; i++) {
        var v = values[i];
        a.push(v | 0, v >>> 0, String(v), Number(String(v)) === v, v + 0.25);
    }
    return a.join(",");
});

// Arrays in each of the shapes the engine gives them.
run("array-shapes", function (k) {
    var ints = [1, 2, 3], doubles = [1.5, 2.5, 3.5], mixed = [1, "two", 3.5, null];
    var holes = [1, , 3];
    ints.push(k); doubles.push(k + 0.5); mixed.push(k);
    return [ints.join("|"), doubles.join("|"), mixed.join("|"), holes.length,
            String(holes[1]), ints.indexOf(3), doubles[1] + doubles[2],
            mixed.slice(1, 3).join("/"), ints.reduce(function (a, b) { return a + b; }, 0)].join(",");
});

// Typed arrays and the bytes underneath them, which is where byte order is
// not an implementation detail but the answer.
run("typed-arrays", function (k) {
    var u32 = new Uint32Array([0x01020304, k]);
    var u8 = new Uint8Array(u32.buffer);
    var f64 = new Float64Array([1.5, -2.25]);
    var f8 = new Uint8Array(f64.buffer);
    var i16 = new Int16Array(u32.buffer);
    var dv = new DataView(u32.buffer);
    return [u8[0], u8[1], u8[2], u8[3], f8[0], f8[7], i16[0], i16[1],
            dv.getUint32(0), dv.getUint32(0, true), dv.getFloat64(0),
            u32[0] >>> 24, u32[1]].join(",");
});

// Reading and writing a typed array through the compiler's fast paths.
run("typed-array-loop", function (k) {
    var a = new Int32Array(64), f = new Float32Array(64), d = new Float64Array(64);
    for (var i = 0; i < 64; i++) { a[i] = i * k; f[i] = i / 3; d[i] = i / 7; }
    var s = 0, t = 0, u = 0;
    for (i = 0; i < 64; i++) { s += a[i]; t += f[i]; u += d[i]; }
    return [s, t.toFixed(4), u.toFixed(6), a[63], f[9].toFixed(6), d[9].toFixed(9)].join(",");
});

// Strings and the numbers that come out of them.
run("strings", function (k) {
    var s = "The quick brown fox " + k;
    return [s.length, s.charCodeAt(4), s.indexOf("brown"), s.toUpperCase(),
            s.slice(4, 9), s.split(" ").length, parseInt(s.slice(-3), 10),
            ("" + (k / 3)).length, s.charAt(0), String.fromCharCode(65, 0x4e2d)].join(",");
});

// Objects, prototypes and the inline caches the compiler builds on.
run("objects", function (k) {
    function Point(x, y) { this.x = x; this.y = y; }
    Point.prototype.len = function () { return Math.sqrt(this.x * this.x + this.y * this.y); };
    var p = new Point(k % 13, k % 7), o = { a: 1, b: "two", c: [3] };
    o.d = k;
    var keys = [];
    for (var key in o) keys.push(key);
    return [p.len().toFixed(6), keys.join("+"), o.c[0], "a" in o, delete o.b, o.b,
            JSON.stringify(o), Object.keys(o).length].join(",");
});

// A type that changes once the function is already compiled: the compiler
// has to leave its own code correctly, carrying the live values with it.
var osrValues = [1, 2, 3.5, "four", null, true, {}, [5], undefined];
run("osr-exit", function (k) {
    function add(a, b) { return a + b; }
    var v = osrValues[k % osrValues.length];
    var out = [];
    for (var i = 0; i < 20; i++) out.push(String(add(i, v)));
    return out.join(",");
});

// Leaving compiled code with doubles and integers live at the same time.
run("osr-exit-values", function (k) {
    function f(n, flip) {
        var i = n | 0, d = n / 3, s = "s" + n, big = n * 1e18;
        if (flip) return [i, d.toFixed(6), s, big].join("/");
        return (i + d + big).toFixed(3) + s;
    }
    var out = [];
    for (var i = 0; i < 30; i++) out.push(f(i + k, i === 29));
    return out.join(",");
});

// Arguments, closures and recursion.
run("arguments-closures", function (k) {
    function outer(a, b) {
        var total = arguments.length;
        function inner() { return a + b + total + arguments.length; }
        return inner(1, 2, 3);
    }
    function fact(n) { return n <= 1 ? 1 : n * fact(n - 1); }
    var counter = (function () { var n = k; return function () { return ++n; }; })();
    return [outer(k, 2), outer(k, 2, 9), fact(12), fact(20), counter(), counter()].join(",");
});

// Exceptions thrown out of compiled code.
run("exceptions", function (k) {
    var caught = [];
    for (var i = 0; i < 8; i++) {
        try {
            if (i % 3 === 0) throw new RangeError("r" + i);
            if (i % 3 === 1) (null).x;
            caught.push("ok" + (i + k));
        } catch (e) {
            caught.push(e.constructor.name);
        } finally {
            caught.push("f");
        }
    }
    return caught.join(",");
});

// Comparisons across types, which the compiler specializes hard.
run("comparisons", function (k) {
    var out = [], values = [0, -0, 1, -1, k, 0.5, "0", "1", "", null, undefined, true, false, NaN];
    for (var i = 0; i < values.length; i++) {
        var a = values[i], b = values[(i + 3) % values.length];
        out.push((a == b ? 1 : 0), (a === b ? 1 : 0), (a < b ? 1 : 0), (a > b ? 1 : 0), String(a + b));
    }
    return out.join(",");
});

// Division and modulo, including the cases that have their own paths.
run("div-mod", function (k) {
    var out = [], n = [1, -1, 3, -3, 7, k + 1, 1073741824, -2147483648];
    for (var i = 0; i < n.length; i++)
        for (var j = 0; j < n.length; j++)
            out.push((n[i] / n[j]).toFixed(6), (n[i] % n[j]).toFixed(6), (n[i] / n[j]) | 0);
    return out.join(",");
});

// Math, where PowerPC has instructions of its own for some of it.
run("math", function (k) {
    var x = (k % 50) + 0.25, out = [];
    var fns = ["abs", "ceil", "floor", "round", "sqrt", "log", "exp", "sin", "cos", "tan", "atan"];
    for (var i = 0; i < fns.length; i++) out.push(Math[fns[i]](x).toFixed(8));
    out.push(Math.pow(x, 2.5).toFixed(6), Math.atan2(x, 3).toFixed(8), Math.min(x, 3), Math.max(x, 3));
    return out.join(",");
});

// Sorting, which mixes compiled comparators with the engine's own code.
run("sort", function (k) {
    var a = [];
    for (var i = 0; i < 200; i++) a.push(((i * 2654435761) % 10007) - 5000 + k);
    a.sort(function (x, y) { return x - y; });
    var b = a.slice().sort();
    return [a[0], a[100], a[199], b[0], b[199], a.join("").length].join(",");
});

// Growing and shrinking, so the compiler sees the storage move underneath it.
run("array-storage", function (k) {
    var a = [];
    for (var i = 0; i < 300; i++) { a.push(i + k); if (i % 7 === 0) a.unshift(-i); }
    while (a.length > 150) a.pop();
    a.splice(10, 5, "x", "y");
    return [a.length, a[0], a[10], a[149], a.indexOf("y"), a.lastIndexOf(20)].join(",");
});

print("done");
