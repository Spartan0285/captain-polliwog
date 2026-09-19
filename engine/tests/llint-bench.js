// Interpreter micro-benchmarks: C loop vs native LLInt vs baseline JIT.
// Run with: jsc llint-bench.js  (prints one line per test, then a checksum)

function time(name, f) {
    var start = Date.now();
    var result = f();
    print(name + ": " + (Date.now() - start) + " ms (" + result + ")");
    return result;
}

var checksum = 0;

checksum += time("int loop", function () {
    var s = 0;
    for (var i = 0; i < 3000000; i++)
        s = (s + i * 3) | 0;
    return s;
});

checksum += time("double math", function () {
    var s = 0.5;
    for (var i = 0; i < 1000000; i++)
        s = s * 1.000001 + i / 3;
    return Math.round(s) % 1000;
});

checksum += time("property access", function () {
    var o = { a: 1, b: 2, c: 3 };
    var s = 0;
    for (var i = 0; i < 1000000; i++) {
        o.a = o.b + o.c;
        s += o.a;
    }
    return s;
});

checksum += time("calls", function () {
    function add(a, b) { return a + b; }
    var s = 0;
    for (var i = 0; i < 1000000; i++)
        s = add(s, i) | 0;
    return s;
});

checksum += time("closures", function () {
    var fns = [];
    for (var i = 0; i < 100000; i++)
        fns.push(function (x) { return function () { return x * 2; }; }(i));
    var s = 0;
    for (var j = 0; j < fns.length; j++)
        s += fns[j]();
    return s;
});

checksum += time("arrays", function () {
    var a = [];
    for (var i = 0; i < 300000; i++)
        a.push(i ^ 0x55);
    a.sort(function (x, y) { return x - y; });
    var s = 0;
    for (var j = 0; j < a.length; j += 7)
        s += a[j];
    return s;
});

checksum += time("strings", function () {
    var parts = [];
    for (var i = 0; i < 100000; i++)
        parts.push("item" + i);
    var joined = parts.join(",");
    return joined.split(",").length + joined.indexOf("item99999");
});

checksum += time("objects", function () {
    function Point(x, y) { this.x = x; this.y = y; }
    Point.prototype.len = function () { return this.x * this.x + this.y * this.y; };
    var s = 0;
    for (var i = 0; i < 300000; i++)
        s += new Point(i & 15, 3).len();
    return s;
});

checksum += time("switch and branches", function () {
    var s = 0;
    for (var i = 0; i < 1000000; i++) {
        switch (i & 7) {
        case 0: s += 1; break;
        case 1: s -= 2; break;
        case 2: s ^= 3; break;
        case 3: s = s * 2 | 0; break;
        default: s += i & 3;
        }
    }
    return s;
});

checksum += time("try/catch", function () {
    var s = 0;
    for (var i = 0; i < 20000; i++) {
        try {
            if (i % 3 == 0)
                throw new Error("x" + i);
            s += i;
        } catch (e) {
            s += e.message.length;
        }
    }
    return s;
});

print("checksum: " + checksum);
